#!/usr/bin/env bash
# Live view of the deploy that step 1 of the demo runs in the background: one
# progress bar per phase (destroy dev, destroy prod, deploy dev, deploy prod)
# and the last resources Terraform has worked on. The demo opens it in a new
# terminal window; it can also be run by hand: bash scripts/deploy-watch.sh
#
# Progress is read from the log: Terraform prints "Plan: A to add, C to
# change, D to destroy" and then one "... complete" line per resource.

cd "$(dirname "$0")/.." || exit 2
LOG=.demo/deploy.log
DONE=.demo/deploy.done
PHASES=("destroy dev" "destroy prod" "deploy dev" "deploy prod")

if [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=''; DIM=''; GREEN=''; RED=''; RESET=''
fi

clock() { printf '%02d:%02d' $(($1 / 60)) $(($1 % 60)); }

# The lines of one phase: from its "### phase" marker to the next marker.
section() { awk -v p="### $1" '$0 == p {on = 1; next} /^### / {on = 0} on' "$LOG" 2>/dev/null; }

bar() {
  local done=$1 total=$2 width=36 fill
  [ "$total" -gt 0 ] || total=1
  [ "$done" -gt "$total" ] && done=$total
  fill=$((done * width / total))
  printf '%s%s' "$(printf '%*s' "$fill" '' | tr ' ' '#')" "$(printf '%*s' $((width - fill)) '' | tr ' ' '.')"
}

draw() {
  local p lines total done kind started
  started=$(cat .demo/deploy.start 2>/dev/null || date +%s)
  printf '\033[H\033[2J'
  printf ' %sDeploy from nothing: dev and prod, side by side%s   %s\n\n' "$BOLD" "$RESET" "$(clock $(($(date +%s) - started)))"
  for p in "${PHASES[@]}"; do
    lines=$(section "$p")
    if [ "${p%% *}" = destroy ]; then kind=destroy; else kind=add; fi
    total=$(printf '%s\n' "$lines" | sed -n "s/.*Plan: \\([0-9]*\\) to add, \\([0-9]*\\) to change, \\([0-9]*\\) to destroy.*/\\1 \\3/p" | tail -1 |
      awk -v k="$kind" '{print (k == "add") ? $1 : $2}')
    done=$(printf '%s\n' "$lines" | grep -c -E "(Creation|Destruction) complete")
    if [ -z "$lines" ]; then
      printf '   %-13s %s%s%s\n' "$p" "$DIM" "waiting" "$RESET"
    elif printf '%s\n' "$lines" | grep -q -E 'Apply complete|Destroy complete|No changes'; then
      printf '   %-13s %s[%s] done%s\n' "$p" "$GREEN" "$(bar 1 1)" "$RESET"
    else
      printf '   %-13s [%s] %s/%s\n' "$p" "$(bar "$done" "${total:-0}")" "$done" "${total:-?}"
    fi
  done
  printf '\n %sLast resources:%s\n' "$DIM" "$RESET"
  grep -E '(Creating|Destroying|Creation complete|Destruction complete)' "$LOG" 2>/dev/null | tail -n 8 |
    sed -E 's/^/   /' | cut -c1-90
}

while [ ! -f "$DONE" ]; do
  draw
  sleep 1
done
draw
read -r rc took <"$DONE"
echo
if [ "$rc" = 0 ]; then
  printf ' %sDeployed in %s. dev and prod are up.%s\n' "$GREEN" "$(clock "$took")" "$RESET"
else
  printf ' %sThe deploy failed; see %s.%s\n' "$RED" "$LOG" "$RESET"
fi
# In its own window it stays open to be read; inline (make demo-deploy) it ends.
if [ -z "${WATCH_INLINE:-}" ]; then
  printf ' %sThis window can be closed.%s\n' "$DIM" "$RESET"
  read -r -t 600 _ </dev/tty
fi
