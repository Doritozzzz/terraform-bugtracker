#!/usr/bin/env bash
# Guided demonstration for a 10-minute talk. One ENTER per step. Step 1 always
# destroys dev and prod and deploys them again from nothing, in the background,
# while the next steps explain the design.
#
#   make demo          every step, step 1 live
#   make demo-deploy   step 1 only, waiting until both environments are up
#   make demo-talk     from step 2 (after make demo-deploy)
#
#   bash scripts/demo.sh --list            the steps
#   bash scripts/demo.sh --map             requirement -> file:line (no Docker needed)
#   bash scripts/demo.sh --access          URLs, users and passwords
#   bash scripts/demo.sh --from N --to M   a range of steps
#   bash scripts/demo.sh --auto            no pauses (to rehearse)
#
# Step 8 scales prod to five replicas and step 11 stops a web replica to fire
# an alert. If the demo ends early (q, Ctrl+C or an error), both are undone.

set -u
cd "$(dirname "$0")/.." || exit 2

AUTO=0
FROM=1
TO=99
MODE=run
while [ $# -gt 0 ]; do
  case $1 in
    --auto) AUTO=1 ;;
    --from) FROM=$2; shift ;;
    --to) TO=$2; shift ;;
    --list) MODE=list ;;
    --map) MODE=map ;;
    --access) MODE=access ;;
    *) echo "unknown option: $1 (see the top of $0)"; exit 2 ;;
  esac
  shift
done

# ------------------------------------------------------------------ terminal

W=$(tput cols 2>/dev/null || echo 90)
[ "$W" -gt 96 ] && W=96
[ "$W" -lt 72 ] && W=72
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; RESET=''
fi

rule() { printf ' %s\n' "$(printf '%*s' $((W - 2)) '' | tr ' ' '-')"; }

# label NAME text...: each text wrapped in a column next to a fixed label.
label() {
  local name=$1
  shift
  printf '%s\n' "$@" | fold -s -w $((W - 10)) |
    awk -v l="$name" -v c="${LABEL_COLOR:-}" -v r="$RESET" \
      'NR == 1 {printf " %s%-6s%s %s\n", c, l, r, $0; next} {printf "        %s\n", $0}'
}

headline() { printf '%s\n' "$*" | fold -s -w $((W - 2)) | sed "s/^/ $BOLD/; s/\$/$RESET/"; echo; }
why()  { label WHY "$@"; }
open() { LABEL_COLOR=$YELLOW label OPEN "$@"; }
ok()   { printf '          %s%s%s\n' "$GREEN" "$*" "$RESET"; }
bad()  { printf '          %s%s%s\n' "$RED" "$*" "$RESET"; }
kv()   { printf '          %-11s %s\n' "$1" "$2"; }

# code FILE PATTERN: FILE:LINE of the first match, read now, so it is never stale.
code() {
  local n
  n=$(grep -n -m 1 -E -- "$2" "$1" 2>/dev/null | cut -d: -f1)
  if [ -n "$n" ]; then label CODE "$1:$n"; else LABEL_COLOR=$RED label CODE "$1 (not found: $2)"; fi
}

# run "command": shows what the step runs; the step prints its result after it.
run() { label RUN "$DIM\$ $1$RESET"; }

# show "command": prints the command and runs exactly that text, so it can be
# copied into any terminal; its output is indented under it.
show() {
  label RUN "$DIM\$ $1$RESET"
  eval "$1" 2>&1 | tr -d '\r' | sed 's/^/          /'
}

clock() { printf '%02d:%02d' $(($1 / 60)) $(($1 % 60)); }

# step N "title" TARGET_SECONDS
step() {
  local right left
  right="$(clock $((SECONDS - START))) | target $(clock "$3")"
  left="STEP $1/$TOTAL  $2"
  printf '\n %s%s%*s%s\n' "$BOLD" "$left" $((W - 2 - ${#left})) "$right" "$RESET"
  rule
  deploy_line
}

gate() {
  rule
  [ "$AUTO" = 1 ] && return 0
  local answer
  printf ' %sENTER next    q quit%s ' "$DIM" "$RESET"
  read -r answer </dev/tty || exit 0
  [ "$answer" = q ] && exit 0
  return 0
}

# ------------------------------------------------------------------- helpers

tfout() { terraform -chdir="environments/$1" output -raw "$2" 2>/dev/null; }
count() { docker ps -q --filter label=project=bugtracker --filter "label=environment=$1" | wc -l | tr -d ' '; }
healthy() { [ "$(docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null)" = healthy ]; }
started() { docker inspect -f '{{.State.StartedAt}}' "$1" 2>/dev/null; }
web_count() { docker ps -q --filter name=bugtracker-prod-web- "${@:1}" | wc -l | tr -d ' '; }

promq() {
  docker exec bugtracker-prod-prometheus wget -qO- "http://127.0.0.1:9090/api/v1/query?query=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")" |
    python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")' 2>/dev/null
}
UP_QUERY='sum(haproxy_server_status{proxy="app",state="UP"})'
replicas_up_is() { [ "$(promq "$UP_QUERY")" = "$1" ]; }

mail_subjects() {
  curl -s -u "admin:$(tfout prod admin_password)" "$(tfout prod mail_url | sed 's|/$||')/api/v1/messages" |
    python3 -c 'import sys,json; [print(m["Subject"]) for m in json.load(sys.stdin)["messages"]]' 2>/dev/null
}
mail_has() { mail_subjects | grep -q "$1"; }

# wait_for SECONDS command...: retries every 2 s.
wait_for() {
  local t0=$SECONDS limit=$1
  shift
  until "$@" >/dev/null 2>&1; do
    [ $((SECONDS - t0)) -ge "$limit" ] && return 1
    sleep 2
  done
}

# The deploy runs in the background, so its state lives in files (ignored by git).
RUNDIR=.demo
deploy_running() { [ -f "$RUNDIR/deploy.pid" ] && kill -0 "$(cat "$RUNDIR/deploy.pid")" 2>/dev/null; }
deploy_since() { echo $(($(date +%s) - $(cat "$RUNDIR/deploy.start"))); }

# Shown under the title while the deploy runs.
deploy_line() {
  if deploy_running; then
    printf ' %sdeploy running %s · dev %s · prod %s containers up%s\n\n' "$DIM" "$(clock "$(deploy_since)")" "$(count dev)" "$(count prod)" "$RESET"
  else
    echo
  fi
}

# ----------------------------------------------------- browser, terminal, clipboard
# Conveniences only: each one does nothing when the tool it needs is missing,
# and never stops the demo.

# A graphical session to open windows in (Linux needs DISPLAY or WAYLAND_DISPLAY).
has_gui() { [ "$(uname)" = Darwin ] || [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; }

# detach command...: runs it apart from the demo, with no output.
detach() {
  if command -v setsid >/dev/null; then setsid "$@" >/dev/null 2>&1 &
  else nohup "$@" >/dev/null 2>&1 &
  fi
}

# The command of the default browser when it is a known one, so several URLs
# can go in one call. Read from xdg-settings: Firefox (also Flatpak and Snap),
# Chrome, Chromium, Brave, Edge or Vivaldi.
browser_cmd() {
  local d b
  command -v xdg-settings >/dev/null || return 1
  d=$(xdg-settings get default-web-browser 2>/dev/null) || return 1
  case $d in
    *firefox*) set -- firefox firefox-esr ;;
    *brave*) set -- brave-browser brave-browser-stable brave ;;
    *chromium*) set -- chromium chromium-browser ;;
    *chrome*) set -- google-chrome-stable google-chrome ;;
    *edge*) set -- microsoft-edge-stable microsoft-edge ;;
    *vivaldi*) set -- vivaldi-stable vivaldi ;;
    *) return 1 ;;
  esac
  for b in "$@"; do command -v "$b" >/dev/null && echo "$b" && return 0; done
  # Installed as a Flatpak: the desktop file name is the application ID.
  command -v flatpak >/dev/null && flatpak info "${d%.desktop}" >/dev/null 2>&1 && echo "flatpak run ${d%.desktop}" && return 0
  return 1
}

# browse URL...: opens the URLs as tabs of the open browser window, in one
# call so no tab gets lost (several calls in a row can drop one). An unknown
# browser gets one xdg-open (or open, on macOS) per URL instead.
browse() {
  has_gui || return 0
  local cmd url args=()
  if cmd=$(browser_cmd); then
    # Firefox opens a list of URLs in a new window unless each is a --new-tab.
    for url in "$@"; do
      case $cmd in *firefox*) args+=(--new-tab "$url") ;; *) args+=("$url") ;; esac
    done
    # shellcheck disable=SC2086  # "flatpak run <id>" holds arguments
    detach $cmd "${args[@]}"
  elif [ "$(uname)" = Darwin ]; then
    detach open "$@"
  elif command -v xdg-open >/dev/null; then
    for url in "$@"; do detach xdg-open "$url"; sleep 1.5; done
  fi
  return 0
}

# Opens scripts/deploy-watch.sh (progress bars of the deploy) in a new window:
# the terminal the demo runs in if it is known, else the first one installed.
# Returns 1 when none can be opened.
open_watcher() {
  has_gui || return 1
  local run="cd '$PWD' && exec bash scripts/deploy-watch.sh" t
  local -a order=()
  [ -n "${KITTY_WINDOW_ID:-}" ] && order+=(kitty)
  [ -n "${WEZTERM_PANE:-}" ] && order+=(wezterm)
  [ -n "${ALACRITTY_WINDOW_ID:-}" ] && order+=(alacritty)
  [ -n "${KONSOLE_VERSION:-}" ] && order+=(konsole)
  [ -n "${GNOME_TERMINAL_SCREEN:-}" ] && order+=(gnome-terminal)
  [ "${TERM_PROGRAM:-}" = Apple_Terminal ] && order+=(Terminal)
  order+=(kitty ptyxis gnome-terminal konsole xfce4-terminal tilix alacritty foot wezterm x-terminal-emulator xterm Terminal)
  for t in "${order[@]}"; do
    case $t in
      Terminal) [ "$(uname)" = Darwin ] || continue
        detach osascript -e "tell application \"Terminal\" to do script \"$run\"" ;;
      *) command -v "$t" >/dev/null || continue
        case $t in
          kitty) detach kitty --title Deploy bash -c "$run" ;;
          ptyxis) detach ptyxis --new-window -- bash -c "$run" ;;
          gnome-terminal) detach gnome-terminal -- bash -c "$run" ;;
          wezterm) detach wezterm start -- bash -c "$run" ;;
          xfce4-terminal | terminator) detach "$t" -x bash -c "$run" ;;
          *) detach "$t" -e bash -c "$run" ;;
        esac ;;
    esac
    return 0
  done
  return 1
}

# copy TEXT: to the clipboard, when a clipboard tool is installed.
copy() {
  has_gui || return 1
  if command -v wl-copy >/dev/null && [ -n "${WAYLAND_DISPLAY:-}" ]; then printf '%s' "$1" | wl-copy
  elif command -v xclip >/dev/null; then printf '%s' "$1" | xclip -selection clipboard
  elif command -v xsel >/dev/null; then printf '%s' "$1" | xsel --clipboard --input
  elif command -v pbcopy >/dev/null; then printf '%s' "$1" | pbcopy
  else return 1
  fi 2>/dev/null
}

deploy_result() {
  local rc took
  read -r rc took <"$RUNDIR/deploy.done" 2>/dev/null
  if [ "${rc:-1}" = 0 ]; then
    ok "deployed in $(clock "$took"): dev $(count dev), prod $(count prod) containers"
  else
    bad "the deploy failed; last lines of $RUNDIR/deploy.log:"
    tail -n 8 "$RUNDIR/deploy.log" | sed 's/^/          /'
  fi
}

# Undo what the demo changed if it ends early.
REPLICA_DOWN=0
SCALED=0
restore() {
  [ "$REPLICA_DOWN" = 1 ] && docker start bugtracker-prod-web-2 >/dev/null 2>&1
  [ "$SCALED" = 1 ] && make --no-print-directory up ENV=prod >/dev/null 2>&1
  return 0
}

# ------------------------------------------------------------------- access

access() {
  local e
  for e in prod dev; do
    if [ -z "$(tfout "$e" app_url)" ]; then printf ' %s: not deployed\n' "$e"; continue; fi
    printf ' %s%-10s %-34s %-6s %s%s\n' "$BOLD" "$e" "" "user" "password" "$RESET"
    printf '   %-8s %-34s %-6s %s\n' \
      app "$(tfout "$e" app_url)" - - \
      admin "$(tfout "$e" admin_url)" admin "$(tfout "$e" admin_password)" \
      grafana "$(tfout "$e" grafana_url)" admin "$(tfout "$e" grafana_password)" \
      minio "$(tfout "$e" storage_console_url)" admin "$(tfout "$e" storage_console_password)"
  done
}

# --------------------------------------------------------------------- map

# section|requirement|file|pattern (extended regular expression)
MAP=(
  "Load balancer|HAProxy container|modules/load-balancer/main.tf|resource \"docker_container\" \"haproxy\""
  "Load balancer|Policy static-rr (default)|modules/load-balancer/variables.tf|default = \"static-rr\""
  "Load balancer|Health checks + passive checks|modules/load-balancer/haproxy.cfg.tftpl|default-server check"
  "Load balancer|Retry on another replica|modules/load-balancer/haproxy.cfg.tftpl|option redispatch"
  "Load balancer|Reload instead of replace|modules/load-balancer/main.tf|resource \"terraform_data\" \"reload\""
  "Load balancer|Replica shown in the page|modules/load-balancer/haproxy.cfg.tftpl|X-Served-By"
  "Replicas|dev: 2 replicas|environments/dev/terraform.tfvars|web_replicas"
  "Replicas|prod: 3 replicas|environments/prod/terraform.tfvars|web_replicas"
  "Replicas|N identical containers (count)|modules/web/main.tf|count *="
  "High availability|Restart policy in prod|environments/prod/main.tf|restart *= \"unless-stopped\""
  "High availability|Memory limits in prod|environments/prod/main.tf|memory *="
  "Cache|Redis only in prod|environments/prod/main.tf|module \"cache\""
  "Cache|Pure cache: LRU, no snapshots|modules/cache/main.tf|allkeys-lru"
  "Object storage|MinIO container|modules/object-storage/main.tf|resource \"docker_container\" \"minio\""
  "Object storage|Init script: bucket, policy, upload|modules/object-storage/init.sh|mb --ignore-existing"
  "Object storage|/images/ served from the bucket|environments/prod/main.tf|path_prefix = \"/"
  "Monitoring|Prometheus scrape jobs|environments/prod/main.tf|scrape_jobs = \\["
  "Monitoring|CPU, memory, health (cAdvisor)|modules/container-metrics/main.tf|resource \"docker_container\""
  "Monitoring|Dashboards as code|monitoring/dashboards/status.json|\"title\": \"Bugtracker status\""
  "Logs|Collector (Alloy)|modules/log-collector/config.alloy.tftpl|loki.source.docker \""
  "Logs|Store with retention (Loki)|modules/log-store/main.tf|retention"
  "Logs|Request ID on every request|modules/load-balancer/haproxy.cfg.tftpl|unique-id-format"
  "Alerts|Alert rules|monitoring/alerts/bugtracker.rules.yml|alert: WebReplicaDown"
  "Alerts|Rule unit tests|monitoring/alerts/bugtracker.test.yml|rule_files"
  "Alerts|Email + Telegram receivers|modules/alert-manager/alertmanager.yml.tftpl|telegram_configs"
  "Security|Admin network (internal)|environments/prod/main.tf|resource \"docker_network\" \"admin\""
  "Security|Admin gateway with login|modules/admin-gateway/haproxy.cfg.tftpl|userlist"
  "Security|Ports on 127.0.0.1 only|modules/load-balancer/main.tf|ip *= \"127.0.0.1\""
  "Security|Read-only, no capabilities|modules/web/main.tf|read_only"
  "Security|Generated passwords|modules/database/main.tf|resource \"random_password\""
  "Terraform|One root per environment|environments/prod/main.tf|module \"web\""
  "Terraform|Settings per environment|environments/prod/terraform.tfvars|web_replicas"
  "Terraform|Makefile: deploy both|Makefile|^up-all:"
  "Terraform|Makefile: stop any container|Makefile|^kill:"
  "Terraform|End-to-end tests|scripts/test.sh|^section \"1"
)

map() {
  local last='' row section req file pattern n
  for row in "${MAP[@]}"; do
    IFS='|' read -r section req file pattern <<<"$row"
    [ "$section" != "$last" ] && printf '\n %s%s%s\n' "$BOLD" "$section" "$RESET" && last=$section
    n=$(grep -n -m 1 -E -- "$pattern" "$file" 2>/dev/null | cut -d: -f1)
    if [ -n "$n" ]; then
      printf '   %-38s %s:%s\n' "$req" "$file" "$n"
    else
      printf '   %-38s %s%s (not found)%s\n' "$req" "$RED" "$file" "$RESET"
    fi
  done
  echo
}

# -------------------------------------------------------------------- steps

TITLES=(
  ""
  "Deploy everything from nothing"
  "Architecture"
  "Reusable modules"
  "One root per environment"
  "Load balancing and HA: the design"
  "Deployed: how to get in"
  "Load balancing, live"
  "Scaling out with no downtime"
  "Back to what the code says"
  "Cache and object storage"
  "A replica fails"
  "Dashboards and a Prometheus query"
  "The alert reaches the team"
  "Tracing one request"
  "Recovery"
  "Secure by default"
)
# Seconds from the start by which each step should be done (10-minute talk).
TARGETS=(0 20 80 120 150 195 240 270 320 350 375 400 450 495 530 555 590)
TOTAL=$((${#TITLES[@]} - 1))

step_1() {
  headline "Everything starts from nothing: dev and prod are destroyed and deployed again, side by side, from code."
  label RUN "$DIM\$ terraform -chdir=environments/dev destroy -auto-approve$RESET" \
    "$DIM\$ terraform -chdir=environments/prod destroy -auto-approve$RESET" \
    "$DIM\$ make up-all$RESET"
  kv "up-all" "make up ENV=dev, then make up ENV=prod"
  kv "up" "terraform plan -out=tfplan, then terraform apply tfplan"
  kv "before" "$(count dev) dev and $(count prod) prod containers running"
  rm -f "$RUNDIR/deploy.done"
  date +%s >"$RUNDIR/deploy.start"
  # The same commands, one "### phase" marker each so deploy-watch.sh can draw
  # one progress bar per phase. No colours in the log, which it parses.
  (
    export TF_CLI_ARGS=-no-color
    start=$(date +%s)
    rc=0
    for e in dev prod; do
      echo "### destroy $e"
      if [ -f "environments/$e/terraform.tfstate" ]; then
        terraform -chdir="environments/$e" init -input=false &&
          terraform -chdir="environments/$e" destroy -auto-approve -input=false || rc=1
      else
        echo "No changes. Nothing to destroy."
      fi
    done
    for e in dev prod; do
      echo "### deploy $e"
      make --no-print-directory up ENV="$e" || rc=1
    done
    echo "$rc $(($(date +%s) - start))" >"$RUNDIR/deploy.done"
  ) >"$RUNDIR/deploy.log" 2>&1 &
  echo $! >"$RUNDIR/deploy.pid"
  if [ "$TO" = 1 ]; then
    # Only step 1 (before the talk): the progress bars right here.
    kv "progress" "below; it takes about 3 minutes"
    echo
    WATCH_INLINE=1 bash scripts/deploy-watch.sh
    echo
    deploy_result
    return
  fi
  if open_watcher; then
    kv "progress" "in the window that just opened (scripts/deploy-watch.sh)"
  else
    kv "progress" "run bash scripts/deploy-watch.sh in another terminal"
  fi
  why "Infrastructure as code: the same commands rebuild both, on any machine." \
    "Names start with bugtracker-<env>: dev and prod never collide."
  code Makefile '^up-all:'
}

step_2() {
  headline "Two environments, each with its own networks. Only two ports reach the host: the app and the admin gateway."
  browse docs/images/architecture.svg
  open "docs/images/architecture.svg (opened in the browser)"
  why "frontend: the only two ways in" \
    "app, backend: the users' path; the LB never reaches the database" \
    "monitoring: collectors and stores (machines)" \
    "admin: people reach the tools only through the gateway, with a login" \
    "egress: Alertmanager's only way out, for Telegram" \
    "Cloud equivalent: public subnet, private subnets, NAT gateway."
}

step_3() {
  headline "13 reusable modules, one per component, with no project names inside."
  run "ls modules"
  local m
  for m in modules/*/; do
    printf '          %-18s %s\n' "$(basename "$m")" "$(sed -n 1p "$m/README.md" | sed 's/^# //')"
  done
  why "Flat module tree, as Terraform recommends: environments wire them." \
    "Inputs and outputs only; a README per module, generated tables."
  code environments/prod/main.tf 'module "web"'
}

step_4() {
  headline "Same modules, different settings: only terraform.tfvars changes between environments."
  run "terraform.tfvars of dev and prod, by variable"
  printf '          %-14s %-14s %s\n' "" dev prod
  # Every variable set in either file, in order of appearance; "-" when not set.
  local k d p
  for k in $(cat environments/dev/terraform.tfvars environments/prod/terraform.tfvars | sed -n 's/^\([a-z_]*\) *=.*/\1/p' | awk '!seen[$0]++'); do
    d=$(sed -n "s/^$k *= *//p" environments/dev/terraform.tfvars | tr -d '"')
    p=$(sed -n "s/^$k *= *//p" environments/prod/terraform.tfvars | tr -d '"')
    printf '          %-14s %-14s %s\n' "$k" "${d:--}" "${p:--}"
  done
  why "One folder per environment, not workspaces: separate state," \
    "and the differences are visible in Git." \
    "prod adds: 3 replicas, Redis, alerts, restart policy, memory limits."
  code environments/prod/terraform.tfvars 'web_replicas'
}

step_5() {
  headline "HAProxy shares the requests between the replicas and takes out the ones that fail."
  why "HAProxy, not nginx: active health checks and Prometheus metrics come" \
    "  free; in nginx active checks are NGINX Plus only (paid)." \
    "static-rr: strict turns. Our requests are short and similar, so they" \
    "  spread evenly; a recovered replica is back in the turn at once." \
    "roundrobin: measured uneven (13/7)." \
    "leastconn: for long connections; ours last milliseconds." \
    "Health check /live every 2 s; one failed request takes a replica out." \
    "Docker restarts a crashed container (unless-stopped)."
  code modules/load-balancer/variables.tf 'default = "static-rr"'
  code modules/load-balancer/haproxy.cfg.tftpl 'default-server check'
  code environments/prod/main.tf 'restart *= "unless-stopped"'
}

step_6() {
  headline "Both environments are up. Every password is generated by Terraform: none is in the code."
  if deploy_running; then
    printf '          %swaiting for the deploy...%s\n' "$DIM" "$RESET"
    while deploy_running; do sleep 3; done
  fi
  [ -f "$RUNDIR/deploy.done" ] && deploy_result
  run "terraform -chdir=environments/prod plan -detailed-exitcode"
  if terraform -chdir=environments/prod plan -detailed-exitcode -input=false >/dev/null 2>&1; then
    ok "No changes: what runs is what the code says."
  else
    bad "prod differs from its code"
  fi
  echo
  if [ "$ACCESS_OPENED" = 0 ]; then access_open; else access; fi
}

# The access table, and the app and admin gateway opened in the browser.
ACCESS_OPENED=0
access_open() {
  ACCESS_OPENED=1
  access
  echo
  # The first tabs carry the gateway login in their URL, so they open logged
  # in. Prometheus and the MinIO console cannot: their pages fetch their data
  # from their own address, and browsers refuse requests to a URL holding a
  # login (a reload keeps it). They open a few seconds later with a clean URL,
  # and the browser reuses the login of the first tabs.
  local plain admin
  plain=$(tfout prod admin_url)
  admin=${plain/\/\//\/\/admin:$(tfout prod admin_password)@}
  browse "$(tfout prod app_url)/#/system" "$admin/" "$admin/grafana/d/status/bugtracker-status" \
    "$admin/alertmanager/" "$admin/mail/"
  sleep 3
  browse "$plain/prometheus/query" "$plain/minio/"
  open "Opened: the app (System), the admin index, Grafana, Alertmanager," \
    "mailbox, then Prometheus and MinIO, logged in to the gateway." \
    "Grafana and MinIO: their own login, in the table." \
    "Any time: bash scripts/demo.sh --access"
}

step_7() {
  headline "Each page shows the replica that served it. The requests go in turns."
  show "for i in \$(seq 30); do curl -s -D - -o /dev/null $(tfout prod app_url)/live | grep -i x-served-by; done | sort | uniq -c"
  open "App > System: replica badge (top left), colours of Load balancing"
  code modules/load-balancer/haproxy.cfg.tftpl 'X-Served-By'
}

step_8() {
  headline "Scaling out is one number. HAProxy and Prometheus reload their config: nothing is replaced."
  run "terraform -chdir=environments/prod apply -auto-approve -var web_replicas=5"
  local app lb0 good total codes traffic
  app=$(tfout prod app_url)
  kv "meanwhile" "curl $app/live every 0.1 s, counting the answers"
  lb0=$(started bugtracker-prod-lb)
  codes=$(mktemp)
  (while :; do curl -s -o /dev/null -m 2 -w '%{http_code}\n' "$app/live"; sleep 0.1; done) >"$codes" &
  traffic=$!
  SCALED=1
  terraform -chdir=environments/prod apply -auto-approve -input=false -var web_replicas=5 >"$RUNDIR/scale.log" 2>&1
  wait_for 60 sh -c "[ \$(docker ps -q --filter name=bugtracker-prod-web- --filter health=healthy | wc -l) -eq 5 ]"
  sleep 3
  kill "$traffic" 2>/dev/null
  wait "$traffic" 2>/dev/null
  total=$(wc -l <"$codes" | tr -d ' ')
  good=$(grep -c '^200$' "$codes")
  rm -f "$codes"
  kv "replicas" "$(web_count --filter health=healthy) healthy"
  kv "traffic" "$total requests during the change, $((total - good)) failed"
  if [ "$(started bugtracker-prod-lb)" = "$lb0" ]; then kv "HAProxy" "same container, config reloaded"; else kv "HAProxy" "replaced"; fi
  open "App > System: five colours in \"Load balancing\""
  why "Reload, not replace: config folder mounted, checked, then SIGUSR2." \
    "Sent from inside: docker kill would turn off the restart policy."
  code modules/load-balancer/main.tf 'resource "terraform_data" "reload"'
}

step_9() {
  headline "The code still says three, so a normal deploy goes back to it: the code is the truth."
  run "make up ENV=prod"
  make --no-print-directory up ENV=prod >"$RUNDIR/scale.log" 2>&1
  SCALED=0
  wait_for 30 sh -c "[ \$(docker ps -q --filter name=bugtracker-prod-web- | wc -l) -eq 3 ]"
  kv "replicas" "$(web_count) (terraform.tfvars: $(sed -n 's/^web_replicas *= *//p' environments/prod/terraform.tfvars))"
  why "A -var on the command line overrides terraform.tfvars for one run."
}

step_10() {
  headline "prod caches the incident list in Redis. Images come straight from the MinIO bucket."
  local app
  app=$(tfout prod app_url)
  # Drop any entry warmed by the open browser so the first request is a MISS.
  docker exec bugtracker-prod-cache sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 del incidents' >/dev/null 2>&1 || true
  show "for i in 1 2; do curl -s -D - -o /dev/null $app/api/incidents | grep -i x-cache; done"
  show "for u in images/high.png images/; do curl -s -o /dev/null -w \"%{http_code}  /\$u\\n\" $app/\$u; done"
  why "Cache-aside: Redis, else PostgreSQL; kept 60 s, cleared on a write." \
    "/images/ goes from the LB to the bucket: a CDN in front of S3." \
    "Bucket policy: download only, so it cannot be listed (403)."
  code modules/cache/main.tf 'allkeys-lru'
  code modules/object-storage/init.sh 'mb --ignore-existing'
}

step_11() {
  headline "One replica goes down. Users notice nothing: the load balancer stops sending it traffic."
  # Clear any older emails (e.g. from make test) so step 13 waits for this alert.
  curl -s -u "admin:$(tfout prod admin_password)" -X DELETE "$(tfout prod mail_url | sed 's|/$||')/api/v1/messages" >/dev/null 2>&1 || true
  show "make kill-web ENV=prod"
  REPLICA_DOWN=1
  T_DOWN=$SECONDS
  sleep 3
  show "for i in \$(seq 20); do curl -s -o /dev/null -w '%{http_code} ' $(tfout prod app_url)/api/incidents; done; echo"
  why "docker stop is a manual stop: Docker leaves it down, the alert fires." \
    "A crash would be restarted by Docker in under 2 seconds." \
    "Any container can be stopped: make kill NAME=prometheus ENV=prod"
  code modules/load-balancer/haproxy.cfg.tftpl 'default-server check'
}

step_12() {
  headline "Prometheus reads every service every 15 s. Grafana draws it; an alert is a query with a threshold."
  label RUN "PromQL: $UP_QUERY"
  wait_for 30 replicas_up_is 2
  kv "result" "$(promq "$UP_QUERY") replicas up"
  open "Grafana > Bugtracker status: 2 web replicas, CPU and memory" \
    "Prometheus > Query: paste the query above"
  code monitoring/alerts/bugtracker.rules.yml 'alert: WebCapacityLow'
}

step_13() {
  headline "The alert fires after 30 s and reaches the team by email and Telegram."
  local mail
  mail=$(tfout prod mail_url | sed 's|/$||')
  run "curl -s -u admin:$(tfout prod admin_password) $mail/api/v1/messages"
  if wait_for 150 mail_has 'FIRING:1. WebReplicaDown'; then
    kv "subject" "$(mail_subjects | grep -m 1 'FIRING')"
    kv "after" "$((SECONDS - T_DOWN)) s"
  else
    bad "no alert email within 150 s"
  fi
  open "Mailpit (admin gateway > mail) and Telegram on the phone"
  why "for: 30s, so a restart of a few seconds wakes nobody." \
    "Prometheus detects; Alertmanager groups, notifies, says when resolved."
  code monitoring/alerts/bugtracker.rules.yml 'alert: WebReplicaDown'
}

step_14() {
  headline "Every request gets an ID. The logs of every container are in one place, searchable."
  local cmd id
  cmd="curl -s -D - -o /dev/null $(tfout prod app_url)/api/incidents | grep -i x-request-id"
  label RUN "$DIM\$ $cmd$RESET"
  id=$(eval "$cmd" | tr -d '\r' | awk -F': ' '{print $2}')
  kv "request ID" "$id"
  copy "$id" && kv "" "(copied to the clipboard)"
  open "Grafana > Bugtracker logs: paste it in Search." \
    "The line says which replica served it and how long it took."
  why "Alloy follows every container's logs and sends them to Loki;" \
    "Grafana searches them."
  code modules/load-balancer/haproxy.cfg.tftpl 'unique-id-format'
}

step_15() {
  headline "The replica comes back and the load balancer puts it in the rotation by itself."
  show "make start-web ENV=prod"
  REPLICA_DOWN=0
  if wait_for 60 healthy bugtracker-prod-web-2; then ok "web-2 healthy"; else bad "web-2 is not healthy"; fi
  sleep 3
  show "for i in \$(seq 30); do curl -s -D - -o /dev/null $(tfout prod app_url)/live | grep -i x-served-by; done | sort | uniq -c"
  open "App > System: three colours again." \
    "The RESOLVED email and Telegram message follow in about a minute."
}

step_16() {
  headline "Only two ports, both on this machine. Every admin tool is behind the gateway's login."
  local admin
  admin=$(tfout prod admin_url)
  show "docker ps --filter label=environment=prod --format '{{.Names}}  {{.Ports}}' | grep 127.0.0.1"
  show "curl -s -o /dev/null -w '%{http_code}\\n' $admin/prometheus/"
  show "curl -s -o /dev/null -w '%{http_code}\\n' -u admin:$(tfout prod admin_password) $admin/prometheus/-/ready"
  kv "mailbox" "$(mail_subjects | paste -sd'|' | sed 's/|/  |  /g')"
  why "admin network: the management plane; no tool has a port of its own." \
    "No root users, read-only filesystems, no capabilities; secrets never in Git."
  code environments/prod/main.tf 'resource "docker_network" "admin"'
}

# --------------------------------------------------------------------- main

case $MODE in
  list)
    for i in $(seq 1 "$TOTAL"); do printf ' %2d  %s  %s\n' "$i" "$(clock "${TARGETS[$i]}")" "${TITLES[$i]}"; done
    exit 0 ;;
  map) map; exit 0 ;;
  access) access; exit 0 ;;
esac

for tool in docker curl make terraform python3; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool"; exit 2; }
done
mkdir -p "$RUNDIR"
trap restore EXIT
trap 'exit 130' INT TERM

START=$SECONDS
T_DOWN=$SECONDS
[ "$TO" -gt "$TOTAL" ] && TO=$TOTAL

# Started after step 1 (make demo-talk): everything is already deployed, so
# the passwords and the browser tabs come first instead of waiting for step 6.
if [ "$FROM" -gt 1 ] && [ "$FROM" -le 6 ] && ! deploy_running; then
  printf '\n %sBEFORE WE START  Access%s\n' "$BOLD" "$RESET"
  rule
  echo
  access_open
  gate
fi

for i in $(seq "$FROM" "$TO"); do
  step "$i" "${TITLES[$i]}" "${TARGETS[$i]}"
  "step_$i"
  # make demo-deploy (step 1 only) just ends when both environments are up.
  if [ "$TO" = 1 ]; then rule; else gate; fi
done
printf '\n %sDemo finished in %s.%s\n' "$DIM" "$(clock $((SECONDS - START)))" "$RESET"
