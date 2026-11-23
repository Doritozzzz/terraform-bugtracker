#!/usr/bin/env bash
# End-to-end verification of the dev and prod environments deployed with
# Terraform. Prints one PASS or FAIL line per check (INFO lines are
# measurements) and exits with a non-zero status if any check fails.
#
#   make test           converge both environments, then check them
#   FRESH=1 make test   destroy both first (data included) and deploy from nothing
#
# It stops and starts containers to test failures, so it takes a few minutes
# (the alert checks wait for real alert timings).

set -u
cd "$(dirname "$0")/.." || exit 2

for tool in docker curl make terraform python3 awk; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool"; exit 2; }
done

pass=0
fail=0
START=$(date +%s)

# ----------------------------------------------------------------- helpers

ok()      { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad()     { printf 'FAIL  %s\n' "$1"; fail=$((fail + 1)); }
info()    { printf 'INFO  %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

# check "description" command...  passes when the command exits with 0.
check() {
  local desc=$1 out
  shift
  if out=$("$@" 2>&1); then ok "$desc"; else
    bad "$desc"
    printf '%s\n' "$out" | tail -n 3 | sed 's/^/        /'
  fi
}

# expect "description" expected actual
expect() {
  if [ "$3" = "$2" ]; then ok "$1 [$3]"; else bad "$1 (expected '$2', got '$3')"; fi
}

# wait_for seconds command...  retries every 2 s until the command succeeds.
wait_for() {
  local limit=$1
  shift
  for _ in $(seq 1 $((limit / 2))); do "$@" >/dev/null 2>&1 && return 0; sleep 2; done
  return 1
}

mk()      { make --no-print-directory "$@"; }
tfout()   { terraform -chdir="environments/$1" output -raw "$2" 2>/dev/null; }
code()    { curl -s -o /dev/null -m 10 -w '%{http_code}' "$@"; }
header()  { curl -s -D - -o /dev/null -m 10 "${@:2}" | tr -d '\r' | awk -F': ' -v h="$1" 'tolower($1)==h {print $2}'; }
json()    { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }
replica() { header x-instance "$1/status"; }

# Containers of one environment, found by the labels every module sets.
names()   { docker ps -a --filter "label=project=bugtracker" --filter "label=environment=$1" --format '{{.Names}}'; }
running() { docker ps --filter "label=project=bugtracker" --filter "label=environment=$1" --format '{{.Names}}'; }

urlenc()  { python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1"; }

# Prometheus API, called from inside its container (not published in prod).
prom()  { docker exec "bugtracker-$1-prometheus" wget -qO- "http://127.0.0.1:9090/api/v1/$2"; }
promq() { prom "$1" "query?query=$(urlenc "$2")" | json "json.dumps(d['data']['result'])"; }
targets_down() { prom "$1" targets | json "[t['labels']['job'] for t in d['data']['activeTargets'] if t['health'] != 'up']"; }

# Loki API, called from the Grafana container, which is on its network.
loki() {
  docker exec "bugtracker-$1-grafana" wget -qO- \
    "http://bugtracker-$1-loki:3100/loki/api/v1/query_range?limit=1000&since=30m&query=$(urlenc "$2")"
}
loki_lines() { loki "$1" "$2" | json "sum(len(s['values']) for s in d['data']['result'])"; }

grafana() { curl -s -m 10 -u "admin:$(tfout "$1" grafana_password)" "$(tfout "$1" grafana_url)$2"; }

psql_q() { docker exec "bugtracker-$1-db" sh -c "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tAc \"$2\""; }

# n requests through the load balancer; prints how many answered 200.
count_ok() {
  local url=$1 n=$2 good=0
  for _ in $(seq 1 "$n"); do [ "$(code "$url/api/incidents")" = 200 ] && good=$((good + 1)); sleep 0.1; done
  echo "$good"
}

# ---------------------------------------------------------- 1. static checks

section "1. Code checks (no containers needed)"
check "terraform fmt: every file is formatted" terraform fmt -check -recursive
for env in dev prod; do
  check "terraform validate ($env)" terraform -chdir="environments/$env" validate -no-color
done
check "alerting rules are valid and their unit tests pass (promtool)" mk test-alerts
check "no state, plan or secret file is versioned" \
  sh -c '! git ls-files | grep -E "tfstate|tfplan|secrets\.auto\.tfvars$|\.generated/"'

# -------------------------------------------------------------- 2. deploy

section "2. Deploy"
if [ "${FRESH:-0}" = 1 ]; then
  info "FRESH=1: destroying both environments, data included"
  for env in dev prod; do terraform -chdir="environments/$env" destroy -auto-approve -input=false >/dev/null 2>&1; done
  expect "nothing of the project is left" 0 "$(docker ps -aq --filter label=project=bugtracker | wc -l | tr -d ' ')"
fi
t0=$(date +%s)
check "make up-all brings up dev and prod" mk up-all
info "deploy took $(( $(date +%s) - t0 )) s"
for env in dev prod; do
  terraform -chdir="environments/$env" plan -detailed-exitcode -input=false >/dev/null 2>&1
  expect "a second plan of $env has nothing to change (code 0)" 0 "$?"
done

DEV=$(tfout dev app_url)
PROD=$(tfout prod app_url)

for env in dev prod; do
  all=$(names "$env" | wc -l | tr -d ' ')
  wait_for 120 sh -c "[ \$(docker ps --filter label=environment=$env --filter label=project=bugtracker --filter health=starting -q | wc -l) -eq 0 ]"
  unhealthy=$(docker ps --filter "label=environment=$env" --filter label=project=bugtracker --filter health=unhealthy -q | wc -l | tr -d ' ')
  expect "$env: all $all containers running" "$all" "$(running "$env" | wc -l | tr -d ' ')"
  expect "$env: no container is unhealthy" 0 "$unhealthy"
done

# ---------------------------------------------------- 3. app and balancing

section "3. Application and load balancing"
for env in dev prod; do
  url=$(tfout "$env" app_url)
  expect "$env: the page answers through the load balancer" 200 "$(code "$url/")"
  status=$(curl -s -m 5 "$url/status")
  expect "$env: /status reports ok" ok "$(printf '%s' "$status" | json "d['status']")"
done
expect "dev runs in development mode" development "$(curl -s "$DEV/status" | json "d['environment']")"
expect "prod runs in production mode" production "$(curl -s "$PROD/status" | json "d['environment']")"

seen_dev=$(for _ in 1 2 3 4; do replica "$DEV"; done | sort -u | wc -l | tr -d ' ')
seen_prod=$(for _ in 1 2 3 4 5 6; do replica "$PROD"; done | sort -u | wc -l | tr -d ' ')
expect "dev: requests alternate between its 2 replicas" 2 "$seen_dev"
expect "prod: requests alternate between its 3 replicas" 3 "$seen_prod"
check "the page names the replica that served it (Server-Timing header)" \
  sh -c "curl -s -D - -o /dev/null '$PROD/' | grep -qi '^server-timing: instance;desc=\"bugtracker-prod-web-'"

expect "a valid new incident is created" 201 "$(code -X POST "$DEV/api/incidents" -H 'Content-Type: application/json' \
  -d '{"title":"test.sh incident","system_name":"test","priority":"LOW"}')"
expect "an invalid incident is rejected" 400 "$(code -X POST "$DEV/api/incidents" -H 'Content-Type: application/json' -d '{"title":""}')"
expect "the seeded data is there (dev)" 50006 "$(psql_q dev "SELECT count(*) FROM incidents WHERE system_name <> 'test'")"

# ----------------------------------------------------- 4. cache and storage

section "4. Cache (prod) and static files (MinIO)"
expect "dev has the cache disabled" disabled "$(curl -s "$DEV/status" | json "d['services']['cache']['status']")"
curl -s -o /dev/null -X POST "$PROD/api/incidents" -H 'Content-Type: application/json' \
  -d '{"title":"test.sh cache reset","system_name":"test","priority":"LOW"}'
expect "prod: first read after a write is a cache MISS" MISS "$(header x-cache "$PROD/api/incidents")"
expect "prod: the next read is a cache HIT" HIT "$(header x-cache "$PROD/api/incidents")"

for env in dev prod; do
  url=$(tfout "$env" app_url)
  expect "$env: static files are served from the bucket" 200 "$(code "$url/static/styles.css")"
  expect "$env: static files are revalidated (Cache-Control: no-cache)" no-cache "$(header cache-control "$url/static/styles.css")"
  expect "$env: anonymous users cannot list the bucket" 403 "$(code "$url/static/")"
  expect "$env: anonymous users cannot upload" 403 "$(code -X PUT --data x "$url/static/hack.txt")"
done
expect "prod: MinIO publishes no port (no admin console)" "" "$(docker port bugtracker-prod-storage)"

# ------------------------------------------------------------- 5. security

section "5. Hardening"
published=$(docker ps --filter label=project=bugtracker --format '{{.Ports}}' | tr ',' '\n' | grep -- '->' | grep -vc '127.0.0.1:')
expect "every published port listens on 127.0.0.1 only" 0 "$published"
not_ro=$(for c in $(running dev; running prod); do docker inspect -f '{{.Name}} {{.HostConfig.ReadonlyRootfs}}' "$c"; done | grep -c false)
expect "every container has a read-only root filesystem" 0 "$not_ro"
caps=$(for c in $(running dev; running prod); do docker inspect -f '{{.Name}} {{.HostConfig.CapDrop}} {{.HostConfig.SecurityOpt}}' "$c"; done | grep -vc 'ALL.*no-new-privileges')
expect "every container drops all capabilities and blocks privilege escalation" 0 "$caps"
# Two exceptions on purpose: the Docker API proxy and cAdvisor need the Docker
# socket, which belongs to root (both have no capabilities and a read-only
# filesystem, and neither publishes a port).
root=$(for c in $(running dev; running prod); do
  u=$(docker exec "$c" id -u 2>/dev/null || docker inspect -f '{{.Config.User}}' "$c")
  case "$u" in ''|0|root) echo "$c" ;; esac
done | grep -vE 'docker-api|cadvisor' | tr '\n' ' ')
expect "no container runs as root (except the Docker API proxy and cAdvisor)" "" "$root"
expect "/metrics is not reachable through the load balancer" 404 "$(code "$PROD/metrics")"

# ---------------------------------------------------- 6. high availability

section "6. High availability (prod)"
docker stop bugtracker-prod-web-2 >/dev/null
wait_for 30 sh -c "[ \"\$(docker exec bugtracker-prod-prometheus wget -qO- http://bugtracker-prod-lb:8405/metrics | grep -c 'haproxy_server_status{proxy=\"app\",server=\"bugtracker-prod-web-2\",state=\"UP\"} 0')\" = 1 ]"
expect "with one replica stopped, 30 requests in a row all succeed" 30 "$(count_ok "$PROD" 30)"
docker start bugtracker-prod-web-2 >/dev/null
check "the stopped replica comes back healthy" wait_for 60 sh -c '[ "$(docker inspect -f {{.State.Health.Status}} bugtracker-prod-web-2)" = healthy ]'

# A crash is simulated by killing the process from the host (Linux). docker
# kill or stop would count as a manual stop, which the restart policy ignores.
# Where the host cannot see it (Docker Desktop), the process is asked to exit
# from inside instead, which the policy also restarts.
pid=$(docker inspect -f '{{.State.Pid}}' bugtracker-prod-web-1)
before=$(docker inspect -f '{{.RestartCount}}' bugtracker-prod-web-1)
kill -9 "$pid" 2>/dev/null || docker exec bugtracker-prod-web-1 kill -TERM 1
check "a crashed replica is restarted by Docker (restart policy)" \
  wait_for 30 sh -c "[ \$(docker inspect -f {{.RestartCount}} bugtracker-prod-web-1) -gt $before ]"
check "and is healthy again" wait_for 60 sh -c '[ "$(docker inspect -f {{.State.Health.Status}} bugtracker-prod-web-1)" = healthy ]'

# ---------------------------------------------------------- 7. persistence

section "7. Persistence"
rows=$(psql_q dev 'SELECT count(*) FROM incidents')
check "the database container can be replaced (make recreate-db)" mk recreate-db ENV=dev
check "the replaced database is healthy" wait_for 60 sh -c '[ "$(docker inspect -f {{.State.Health.Status}} bugtracker-dev-db)" = healthy ]'
expect "every row survives the replacement (named volume)" "$rows" "$(psql_q dev 'SELECT count(*) FROM incidents')"

# -------------------------------------------------------- 8. observability

section "8. Logs and metrics"
rid=$(header x-request-id "$DEV/api/incidents" -H 'X-Request-ID: forged-by-the-client')
check "the load balancer gives every request a UUID" sh -c "printf '%s' '$rid' | grep -Eq '^[0-9a-f-]{36}$'"
docker stop bugtracker-dev-web-1 bugtracker-dev-web-2 >/dev/null
wait_for 30 sh -c "[ \"\$(curl -s -o /dev/null -w %{http_code} '$DEV/api/incidents')\" = 503 ]"
rid503=$(header x-request-id "$DEV/api/incidents")
expect "with no replica up, the load balancer answers 503" 503 "$(code "$DEV/api/incidents")"
check "and that 503 also carries a request ID" sh -c "printf '%s' '$rid503' | grep -Eq '^[0-9a-f-]{36}$'"
docker start bugtracker-dev-web-1 bugtracker-dev-web-2 >/dev/null
wait_for 60 sh -c "[ \"\$(curl -s -o /dev/null -w %{http_code} '$DEV/api/incidents')\" = 200 ]"
# Dev logs every request at debug level, so the replica line exists too.
services_with() { loki dev "{environment=\"dev\"} |= \"$1\"" | json "' '.join(sorted({s['stream']['service'] for s in d['data']['result']}))"; }
in_both() { [ "$(services_with "$rid")" = 'load-balancer web' ]; }
check "the same request ID is in the load balancer and replica logs (Loki)" wait_for 30 in_both
expect "a client-supplied request ID is replaced" 0 "$(loki_lines dev '{environment="dev"} |= "forged-by-the-client"')"

psql_q prod 'SELECT pg_sleep(0.6)' >/dev/null
slow_lines() { loki_lines prod '{service="database"} |= "duration:" |= "pg_sleep"'; }
slow_logged() { [ "$(slow_lines)" -ge 1 ]; }
check "a slow query (>500 ms) is logged by PostgreSQL and reaches Loki" wait_for 30 slow_logged

for env in dev prod; do
  envs=$(loki "$env" '{environment=~".+"}' | json "sorted({s['stream']['environment'] for s in d['data']['result']})")
  expect "$env: Loki only holds logs of its own environment" "['$env']" "$envs"
  # Earlier checks stopped replicas on purpose: give Prometheus a scrape or two to see them back.
  wait_for 60 eval '[ "$(targets_down '"$env"')" = "[]" ]'
  expect "$env: every Prometheus target is up" "[]" "$(targets_down "$env")"
  others=$(promq "$env" "count by (container_label_environment) (container_last_seen)" | json "sorted(r['metric'].get('container_label_environment') for r in d)")
  expect "$env: container metrics only cover its own environment" "['$env']" "$others"
  for ds in prometheus loki; do
    expect "$env: Grafana's $ds data source works" OK "$(grafana "$env" "/api/datasources/uid/$ds/health" | json "d['status']")"
  done
  expect "$env: both dashboards are provisioned" 2 "$(grafana "$env" '/api/search?tag=bugtracker' | json 'len(d)')"
done
p99=$(promq prod 'histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))' | json "round(float(d[0]['value'][1])*1000, 1) if d else 'no traffic'" 2>/dev/null)
info "prod p99 latency of the last 5 minutes: ${p99} ms"

# ------------------------------------------------------------- 9. alerts

section "9. Alerts (prod)"
expect "Prometheus loaded the 11 alerting rules" 11 "$(prom prod rules | json "sum(len(g['rules']) for g in d['data']['groups'])")"
# Earlier sections stopped containers on purpose; wait for those alerts to clear.
quiet() { [ "$(prom prod alerts | json "len(d['data']['alerts'])")" = 0 ]; }
wait_for 120 quiet
expect "no alert fires while everything is healthy" "[]" "$(prom prod alerts | json "[a['labels']['alertname'] for a in d['data']['alerts']]")"

MAIL=$(tfout prod mail_url)
curl -s -X DELETE "$MAIL/api/v1/messages" >/dev/null
mails() { curl -s "$MAIL/api/v1/messages" | json "' | '.join(m['Subject'] for m in d['messages'])"; }
t0=$(date +%s)
docker stop bugtracker-prod-web-2 >/dev/null
check "a stopped replica fires WebReplicaDown" wait_for 150 sh -c \
  "docker exec bugtracker-prod-prometheus wget -qO- http://127.0.0.1:9090/api/v1/alerts | grep -q '\"alertname\":\"WebReplicaDown\".*\"state\":\"firing\"'"
check "and its email reaches the mailbox" wait_for 60 sh -c "curl -s '$MAIL/api/v1/messages' | grep -q 'FIRING:1\] WebReplicaDown (prod)'"
info "alert email received $(( $(date +%s) - t0 )) s after the replica stopped"
docker start bugtracker-prod-web-2 >/dev/null
check "when it comes back, the resolved email arrives" wait_for 150 sh -c "curl -s '$MAIL/api/v1/messages' | grep -q 'RESOLVED\] WebReplicaDown (prod)'"
info "mailbox: $(mails)"
sent=$(docker exec bugtracker-prod-alertmanager wget -qO- http://127.0.0.1:9093/metrics | awk '/^alertmanager_notifications_total/ && /integration="telegram"/ {s+=$2} END {print s+0}')
failed=$(docker exec bugtracker-prod-alertmanager wget -qO- http://127.0.0.1:9093/metrics | awk '/^alertmanager_notifications_failed_total/ && /integration="telegram"/ {s+=$2} END {print s+0}')
if [ -n "$(tfout prod alertmanager_url)" ] && grep -q telegram_configs "environments/prod/.generated/bugtracker-prod-alertmanager.yml" 2>/dev/null; then
  expect "Telegram notifications sent without failures" 0 "$failed"
  info "Telegram notifications sent by this Alertmanager: $sent"
else
  info "Telegram not configured (no secrets.auto.tfvars): alerts are only emailed"
fi

printf '\n%s passed, %s failed (%s s)\n' "$pass" "$fail" "$(( $(date +%s) - START ))"
[ "$fail" -eq 0 ]
