#!/usr/bin/env bash
# Guided demonstration, sized for a 10-minute talk. Each step says what it
# shows, runs real commands (printed before they run) and says what to look
# at. Press ENTER to go on, q to quit.
#
#   make demo                       guided, one ENTER per step
#   bash scripts/demo.sh --auto     no pauses (to rehearse or check it)
#
# It stops a prod web replica on purpose to fire an alert. If the demo ends
# early (Ctrl+C, q or an error) the replica is started again.

set -u
cd "$(dirname "$0")/.." || exit 2

AUTO=0
[ "${1:-}" = --auto ] && AUTO=1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m'; D=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'; R=$'\033[31m'; N=$'\033[0m'
else
  B=''; D=''; G=''; Y=''; C=''; R=''; N=''
fi

for tool in docker curl make terraform python3; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool"; exit 2; }
done

STEP=0
TOTAL=13
START=$SECONDS
REPLICA_DOWN=0
# Set while prod differs from its code (scaled out, or a replica deleted by hand).
DRIFTED=0

restore() {
  [ "$REPLICA_DOWN" = 1 ] && docker start bugtracker-prod-web-2 >/dev/null 2>&1
  [ "$DRIFTED" = 1 ] && make --no-print-directory up ENV=prod >/dev/null 2>&1
  printf '\n%sDemo finished in %d min %d s.%s\n' "$D" $(((SECONDS - START) / 60)) $(((SECONDS - START) % 60)) "$N"
}
trap restore EXIT
trap 'exit 130' INT TERM

# ------------------------------------------------------------------ helpers

tfout() { terraform -chdir="environments/$1" output -raw "$2" 2>/dev/null; }

pause() {
  [ "$AUTO" = 1 ] && return
  printf '\n%s[ENTER] continue   [q] quit%s ' "$D" "$N"
  read -r answer </dev/tty || exit 0
  [ "$answer" = q ] && exit 0
}

# step "title" "what this step shows"
step() {
  STEP=$((STEP + 1))
  printf '\n%s%s %d/%d  %s %s\n' "$B" "━━━" "$STEP" "$TOTAL" "$1" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$N"
  printf '%s\n' "$2" | fold -s -w 90
}

# run "command": prints it, then runs it.
run() {
  printf '\n%s$ %s%s\n' "$C" "$1" "$N"
  # Terraform colours its output; the codes are removed so every line reads cleanly.
  bash -c "$1" 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g; s/^/  /'
}

look()   { printf '\n%s→ %s%s\n' "$Y" "$1" "$N" | fold -s -w 92; }
result() { printf '%s✔ %s%s\n' "$G" "$1" "$N"; }
problem() { printf '%s✘ %s%s\n' "$R" "$1" "$N"; }

# Waits up to $1 seconds for a command to succeed, printing a dot every 5 s.
wait_until() {
  local limit=$1 t0=$SECONDS
  shift
  until "$@" >/dev/null 2>&1; do
    [ $((SECONDS - t0)) -ge "$limit" ] && { echo; return 1; }
    printf '.'
    sleep 5
  done
  echo
}

mail_subjects() { curl -s "$MAIL/api/v1/messages" | python3 -c 'import sys,json; [print(m["Subject"]) for m in json.load(sys.stdin)["messages"]]'; }
mail_has() { mail_subjects | grep -q "$1"; }
healthy() { [ "$(docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null)" = healthy ]; }
replica_healthy() { healthy bugtracker-prod-web-2; }
# True when 10 requests in a row reach $1 different replicas.
replicas_serving() { [ "$(for i in $(seq 10); do curl -s -D - -o /dev/null -m 2 "$APP/status" | grep -i '^x-instance'; done | sort -u | wc -l)" -eq "$1" ]; }

# ------------------------------------------------------------------- intro

clear 2>/dev/null
printf '%sIT Incident Tracker — Infrastructure as Code with Terraform%s\n' "$B" "$N"
printf 'Two environments, a load balancer, object storage, monitoring, logs and alerts,\n'
printf 'all described in Terraform and deployed on Docker as a simulated cloud.\n'
pause

# ---------------------------------------------------------------- 1. deploy

step "One command deploys everything" \
  "Terraform plans the changes, saves the plan and applies exactly that plan, for dev and for prod. Running it again changes nothing: the code describes the final state, not steps."
run "make up-all 2>&1 | grep -E 'Plan:|No changes|Apply complete'"
run "terraform -chdir=environments/prod plan | grep 'No changes'"
result "Both environments are up, and a second plan has nothing to change."
pause

APP=$(tfout prod app_url)
GRAFANA=$(tfout prod grafana_url)
MAIL=$(tfout prod mail_url)

# ---------------------------------------------------------- 2. environments

step "Two environments running side by side" \
  "Dev and prod are separate Terraform roots with their own state. Every container carries labels with its project, environment and service."
run "make urls"
run "for env in dev prod; do printf '%-5s %s containers\n' \$env \$(docker ps -q --filter label=environment=\$env | wc -l); done"
look "Open the app in prod: $APP"
pause

# -------------------------------------------------------- 3. modules / tfvars

step "Same modules, different settings" \
  "Both environments use the same reusable modules. What changes is a short settings file per environment: prod has three replicas and publishes fewer admin tools."
run "ls modules"
run "grep -v '^#' environments/dev/terraform.tfvars"
run "grep -v '^#' environments/prod/terraform.tfvars"
pause

# --------------------------------------------------------- 4. load balancer

step "The load balancer shares the requests" \
  "HAProxy sends each request to the next replica in turn (static round-robin) and checks every 2 seconds that each replica answers."
run "for i in 1 2 3 4 5 6; do curl -s -D - -o /dev/null $APP/status | grep -i '^x-instance' ; done"
look "In the app, the badge at the top and the System tab show which replica served the page."
pause

# ------------------------------------------------------------ 5. scaling

step "Scaling out is changing one number" \
  "Prod declares three replicas in terraform.tfvars. A -var on the command line takes precedence over that file, so we ask for five without editing it. Terraform adds two replicas and replaces the load balancer and Prometheus, which read their config only when they start. That costs a few seconds without the load balancer, the price of running it as a single container; a managed cloud load balancer adds targets without a gap."
run "terraform -chdir=environments/prod plan -input=false -no-color -var web_replicas=5 -out=tfplan | grep -E '^  # |^Plan:'"
DRIFTED=1
run "make --no-print-directory apply ENV=prod | grep 'Apply complete'"
printf '%sWaiting until the load balancer sends traffic to all five%s' "$D" "$N"
wait_until 60 replicas_serving 5
run "for i in \$(seq 10); do curl -s -D - -o /dev/null $APP/status | grep -i '^x-instance'; done | sort | uniq -c"
look "System tab: the load balancing view shows five colours. Grafana, Status: Requests per replica has five lines."
pause
printf '\n%sThe code still says three, so a normal deploy returns to it:%s\n' "$B" "$N"
run "make --no-print-directory up ENV=prod | grep -E 'Plan:|Apply complete'"
DRIFTED=0
result "Back to the three replicas of terraform.tfvars: the code is the source of truth."
pause

# ----------------------------------------------------- 6. replica failure

step "A replica fails: users notice nothing" \
  "One of the three replicas is stopped. The load balancer takes it out of rotation, so every request still works. This also starts an alert, which we check in step 9."
run "make --no-print-directory kill-web ENV=prod"
REPLICA_DOWN=1
T_DOWN=$SECONDS
curl -s -X DELETE "$MAIL/api/v1/messages" >/dev/null
sleep 8
run "for i in \$(seq 20); do curl -s -o /dev/null -w '%{http_code} ' $APP/api/incidents; done; echo"
look "Grafana, Status dashboard ($GRAFANA): web-2 is DOWN in red, and availability stays at 100%."
pause

# ------------------------------------------------------ 7. object storage

step "Static files come from object storage" \
  "CSS and JavaScript live in a MinIO bucket, the local version of Amazon S3. The load balancer serves them straight from it, like a CDN, so the replicas never handle them."
run "curl -s -D - -o /dev/null $APP/static/styles.css | grep -iE '^HTTP|^x-served-by|^cache-control'"
run "curl -s -o /dev/null -w 'Listing the bucket: HTTP %{http_code}\n' $APP/static/"
result "Anyone can download a file, nobody can list or change the bucket."
pause

# ------------------------------------------------------------ 8. tracing

step "Every request can be traced" \
  "The load balancer gives each request a unique ID, passes it to the replica and returns it to the browser. All container logs go to Loki, so one search finds the whole request."
RID=$(curl -s -D - -o /dev/null "$APP/api/incidents" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-request-id" {print $2}')
printf '\n%s$ curl -s -D - -o /dev/null %s/api/incidents | grep -i x-request-id%s\n  x-request-id: %s\n' "$C" "$APP" "$N" "$RID"
sleep 2
run "docker logs bugtracker-prod-lb 2>/dev/null | grep $RID | cut -c1-140"
look "Grafana, Logs dashboard: paste the ID in Search. The line links to every log line of that request."
pause

# -------------------------------------------------------------- 9. alert

step "The alert reaches the team" \
  "Prometheus noticed the stopped replica. After 30 seconds down (so a quick restart never wakes anyone), Alertmanager sends an email, and a Telegram message when a bot is configured, with a link to the dashboard."
printf '\n%sWaiting for the email%s' "$D" "$N"
if wait_until 150 mail_has 'FIRING.*WebReplicaDown'; then
  result "Email received $((SECONDS - T_DOWN)) s after the replica stopped."
  run "curl -s $MAIL/api/v1/message/latest | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[\"Subject\"]); print(); print(d[\"Text\"].strip())'"
else
  problem "No alert email within 150 s."
fi
look "Mailbox: $MAIL   With a Telegram bot configured, the same message arrives on the phone."
pause

# ---------------------------------------------------------- 10. recovery

step "Recovery" \
  "The replica is started again. The load balancer puts it back in rotation as soon as its health check passes, and Alertmanager sends a 'resolved' notice a minute later."
run "make --no-print-directory start-web ENV=prod"
printf '%sWaiting until it is healthy%s' "$D" "$N"
wait_until 60 replica_healthy && REPLICA_DOWN=0 && result "web-2 is healthy and serving again."
pause

# ------------------------------------------------------- 11. self-healing

step "Self-healing: Docker restarts, Terraform restores" \
  "Two levels. A process that crashes is restarted by Docker in seconds (restart policy). A container deleted by hand is drift: the real infrastructure no longer matches the code, and terraform plan finds it and recreates it."
before=$(docker inspect -f '{{.RestartCount}}' bugtracker-prod-web-1)
printf '\n%s$ kill -9 <PID of web-1 on the host>%s\n' "$C" "$N"
# The host sees the process on Linux; on Docker Desktop it is asked to exit from inside.
kill -9 "$(docker inspect -f '{{.State.Pid}}' bugtracker-prod-web-1)" 2>/dev/null || docker exec bugtracker-prod-web-1 kill -TERM 1
printf '%sWaiting for Docker to restart it%s' "$D" "$N"
wait_until 30 sh -c "[ \$(docker inspect -f '{{.RestartCount}}' bugtracker-prod-web-1) -gt $before ]"
run "docker inspect -f '{{.Name}}: restarted {{.RestartCount}} time(s), {{.State.Status}}' bugtracker-prod-web-1"
run "docker rm -f bugtracker-prod-web-3"
DRIFTED=1
run "make --no-print-directory plan ENV=prod | grep -E '# module|Plan:'"
run "make --no-print-directory apply ENV=prod | grep 'Apply complete'"
printf '%sWaiting until it is healthy%s' "$D" "$N"
wait_until 60 healthy bugtracker-prod-web-3 && DRIFTED=0 && result "web-3 is back, exactly as the code describes it."
pause

# ----------------------------------------------------------- 12. security

step "Secure by default" \
  "Ports only on this machine, no container running as root (two documented exceptions need the Docker socket), read-only filesystems, and secrets never in Git."
run "docker ps --filter label=environment=prod --format '{{.Ports}}' | tr ',' '\n' | grep -o '[0-9.]*:[0-9]*->' | sort -u"
run "for c in bugtracker-prod-web-1 bugtracker-prod-db bugtracker-prod-lb bugtracker-prod-grafana; do printf '%-26s user %s\n' \$c \$(docker exec \$c id -un); done"
run "git check-ignore environments/prod/terraform.tfstate environments/prod/secrets.auto.tfvars"
pause

# -------------------------------------------------------------- 13. tests

step "Everything is tested" \
  "The alert rules have unit tests, and make test checks both environments end to end in 72 checks (its full output is in docs/evidence)."
run "make --no-print-directory test-alerts"
run "tail -n 1 docs/evidence/test-results.txt"
if mail_has 'RESOLVED.*WebReplicaDown'; then result "And the 'resolved' email has already arrived."; fi
