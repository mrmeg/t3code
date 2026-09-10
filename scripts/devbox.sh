#!/usr/bin/env bash
# Operate the Railway devboxes (FORK.md §5.4) without remembering project IDs
# or the quirks of `railway up`.
#
#   scripts/devbox.sh [--box personal|client] <command>
#
#   up        start a stopped box, or push infra/devbox to a running one. When
#             the source is unchanged Railway skips the build, so `up` falls
#             back to `restart`. Either way the new container activates any CLI
#             release staged by devbox-refresh.
#   restart   restart the running container without rebuilding (same effect on
#             staged CLI releases; fastest way to apply an update). Keeps the
#             deployment's environment: after changing a variable, use `up`.
#   down      stop the box (volume persists; only it bills)
#   status    Railway deployment state plus, when up, T3 Connect link + versions
#   refresh   stage the latest CLI release now (applied on the next `up`)
#   ssh [cmd] shell on the box, or run one command
#   logs      tail deploy logs
#   vars      variable names set on the service (values never printed)
#   audit     one-shot inventory: versions, auth, state, processes
#
#   link      one-time T3 Connect sign-in for a client box: opens a shell on the
#             box with the two commands to run while the client is on chat
#
# `railway redeploy` only works while a deployment exists; after `down` there is
# none, so `up` always uploads the image source. The personal box is connected
# to mrmeg/t3code and expects infra/devbox/Dockerfile relative to the archive
# root, while the client box was created from infra/devbox itself and expects
# Dockerfile at the root. `up` stages the right layout for each.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BOX=personal
while [[ $# -gt 0 ]]; do
  case "$1" in
    --box) BOX=$2; shift 2 ;;
    --box=*) BOX=${1#--box=}; shift ;;
    *) break ;;
  esac
done
CMD=${1:-status}; shift || true

case "$BOX" in
  personal)
    PROJECT=5e74fae8-5b59-4f41-b778-f140ec224646
    ENVIRONMENT=dd05b42d-9f69-4165-ac94-40311d2e70eb
    SERVICE=0b64c47f-67e1-4362-9023-99171319c376
    LAYOUT=repo ;;
  client)
    PROJECT=a334dbf3-e0b1-4108-b953-51dfc06f6802
    ENVIRONMENT=972de3b3-54b5-4689-8406-5c83ce04355d
    SERVICE=6da7bde1-e7bb-4f12-b4be-136d882deeec
    LAYOUT=flat ;;
  *) echo "unknown box '$BOX' (personal|client)" >&2; exit 2 ;;
esac

# Target flags go before any `--`, otherwise `railway ssh` passes them to the
# remote command and silently falls back to the linked service.
TARGET=(--project "$PROJECT" --environment "$ENVIRONMENT" --service "$SERVICE")
quiet() { grep -v -e 'newer Railway CLI' -e 'railway upgrade' -e 'Config as Code' -e 'Migrate:' -e 'Existing files keep' -e 'Using SSH key' || true; }
# Latest deployment (what a fresh `up` produces) versus the one actually
# running: after `down` the latest is REMOVED, and after an unchanged `up` it is
# SKIPPED while the previous SUCCESS keeps serving.
deployment_state() {
  railway deployment list "${TARGET[@]}" --json 2>/dev/null | jq -r '.[0] | "\(.status) \(.id) \(.createdAt)"' 2>/dev/null || echo "NONE"
}
active_deployment() {
  railway status --project "$PROJECT" --environment "$ENVIRONMENT" --json 2>/dev/null \
    | jq -r '.environments.edges[0].node.serviceInstances.edges[] | .node | select(.serviceName=="devbox") | .activeDeployments[0]
             | if . == null then "NONE" else "\(.status) \(.id) \(.instances|map(.status)|join(","))" end' 2>/dev/null || echo "NONE"
}
box_is_up() { [[ $(active_deployment) == SUCCESS* ]]; }

# With no running container, `railway ssh` lands on Railway's account endpoint
# and prints a JSON blob with exit 0, so check the deployment first.
box_ssh() {
  box_is_up || { echo "$BOX box is not running (run: scripts/devbox.sh --box $BOX up)" >&2; return 1; }
  railway ssh "${TARGET[@]}" -- "$@" 2>&1 | quiet
}

# Watch the deployment created after `up`: 0 = built and running, 2 = skipped
# (source unchanged), 1 = failed or timed out. $1 is the id that was latest
# before `up`, so a stale read cannot pass for the new one.
wait_for_deploy() {
  local prev=$1 st
  for _ in $(seq 1 45); do
    st=$(deployment_state)
    if [[ ${st#* } != "$prev "* ]]; then
      echo "  $(date +%T) ${st%% *}"
      case "$st" in
        SUCCESS*) return 0 ;;
        SKIPPED*) return 2 ;;
        FAILED*|CRASHED*|REMOVED*) echo "deploy ended: $st" >&2; railway logs "${TARGET[@]}" --build 2>&1 | quiet | tail -20; return 1 ;;
      esac
    fi
    sleep 20
  done
  echo "timed out waiting for deployment" >&2; return 1
}

# The remote command only runs once a container answers; a stopped box returns
# Railway's account JSON with exit 0, hence the marker instead of the exit code.
wait_for_serve() {
  for _ in $(seq 1 30); do
    if railway ssh "${TARGET[@]}" -- sh -c 'pgrep -f "t3 serve" >/dev/null && echo T3_UP' 2>/dev/null | grep -q T3_UP; then
      return 0
    fi
    sleep 10
  done
  echo "t3 serve did not come up" >&2; return 1
}

cmd_up() {
  local stage prev
  prev=$(deployment_state | awk '{print $2}')
  stage=$(mktemp -d)/devbox-up
  if [[ $LAYOUT == repo ]]; then
    mkdir -p "$stage/infra" && cp -R "$REPO_ROOT/infra/devbox" "$stage/infra/"
  else
    mkdir -p "$stage" && cp -R "$REPO_ROOT/infra/devbox/." "$stage/"
  fi
  echo "→ uploading infra/devbox to $BOX box"
  (cd "$stage" && railway up "${TARGET[@]}" --detach 2>&1 | quiet | grep -E 'Build Logs|error' || true)
  wait_for_deploy "$prev" && rc=0 || rc=$?
  case $rc in
    0) ;;
    2) echo "→ source unchanged, Railway skipped the build; restarting the running container instead"
       cmd_restart; return ;;
    *) return 1 ;;
  esac
  echo "→ waiting for t3 serve"
  wait_for_serve
  cmd_status
}

cmd_restart() {
  box_is_up || { echo "$BOX box is not running; use: scripts/devbox.sh --box $BOX up" >&2; return 1; }
  # railway restart (CLI 5.49) restarts the container but never returns, so run
  # it detached and judge success by the box coming back.
  railway restart "${TARGET[@]}" -y </dev/null >/dev/null 2>&1 &
  local cli_pid=$!
  disown "$cli_pid"   # no "Terminated" job notice when it is reaped below
  echo "→ restart requested; waiting for t3 serve"
  sleep 20   # let the old container go away before polling
  wait_for_serve && rc=0 || rc=$?
  kill "$cli_pid" 2>/dev/null || true
  [[ $rc -eq 0 ]] || return "$rc"
  cmd_status
}

cmd_status() {
  echo "Railway ($BOX): active $(active_deployment); latest $(deployment_state | cut -d" " -f1,2)"
  box_is_up || return 0
  box_ssh sh -c '
    printf "boot: t3 serve up %s\n" "$(ps -o etime= -p "$(pgrep -f "t3 serve" | head -1)" 2>/dev/null | tr -d " " || echo "not running")"
    printf "cli:  %s\n" "$(readlink /data/cli/current 2>/dev/null || echo image-baked)"
    for b in t3 claude codex bun eas railway supabase stripe clerk sentry-cli wrangler vercel; do printf "  %-10s %s\n" "$b" "$($b --version 2>/dev/null | head -1 || echo MISSING)"; done
    [ -f /data/cli/next/.complete ] && printf "staged: %s\n" "$(tr "\n" " " < /data/cli/next/.versions)"
    t3 connect status --base-dir /data/t3code 2>/dev/null | sed -n "2,4p"
  ' || echo "(box not reachable over ssh)"
}

cmd_audit() {
  box_ssh sh -c '
    echo "== host"; nproc; free -m | sed -n 2p; df -h /data | tail -1; echo "uid=$(id -u) HOME=$HOME SHELL=$SHELL"
    echo "== versions"; for c in node npm pnpm t3 claude codex bun eas gh git tailscale rg jq fd uv aws railway supabase stripe clerk sentry-cli wrangler vercel; do printf "%-10s %s\n" "$c" "$($c --version 2>/dev/null | head -1 || echo MISSING)"; done
    echo "== cli releases"; ls -1 /data/cli/releases 2>/dev/null; echo "current -> $(readlink /data/cli/current 2>/dev/null)"; tail -3 /data/cli/refresh.log 2>/dev/null
    # Never print a credential, only whether one is there: an identity from the
    # CLIs that can answer offline, a file for the ones whose check costs a
    # network round trip, and set/unset for the token-only ones.
    echo "== auth"
    printf "%-10s %s\n" gh "$(gh auth status 2>&1 | grep -E "Logged in|not logged" | head -1 | sed "s/^ *//")"
    printf "%-10s %s\n" eas "$(eas whoami 2>&1 | head -1)"
    printf "%-10s %s\n" railway "$(railway whoami 2>&1 | head -1)"
    printf "%-10s %s\n" vercel "$(vercel whoami 2>&1 | tail -1)"
    for pair in "supabase:$HOME/.supabase/access-token" "stripe:$HOME/.config/stripe/config.toml" "clerk:$HOME/.clerk/config.json"; do
      printf "%-10s %s\n" "${pair%%:*}" "$([ -s "${pair#*:}" ] && echo "credential on volume" || echo "no credential")"
    done
    for name in SENTRY_AUTH_TOKEN CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID EXPO_TOKEN AWS_BEARER_TOKEN_BEDROCK; do
      printf "%-10s %s\n" "${name%%_*}" "$(grep -q "^export $name=" "$HOME/.config/devbox/env" 2>/dev/null && echo "$name set" || echo "$name unset")"
    done
    echo "== connect"; t3 connect status --base-dir /data/t3code 2>&1 | sed -n "2,5p"
    echo "== tailscale"; tailscale --socket=/var/run/tailscale/tailscaled.sock status 2>&1 | head -1
    echo "== projects"; find /data/work -maxdepth 2 -name .git 2>/dev/null | sed "s#/.git##"
    echo "== processes"; ps -eo pid,etime,cmd --sort=pid | grep -vE "ps -eo|grep" | head -15
  '
}

case "$CMD" in
  up) cmd_up ;;
  restart) cmd_restart ;;
  down) railway down "${TARGET[@]}" -y 2>&1 | quiet ;;
  status) cmd_status ;;
  refresh) box_ssh devbox-refresh ;;
  ssh) if [[ $# -gt 0 ]]; then box_ssh "$@"; else box_is_up && railway ssh "${TARGET[@]}"; fi ;;
  logs) railway logs "${TARGET[@]}" 2>&1 | quiet | tail -40 ;;
  vars) railway variables "${TARGET[@]}" --json 2>/dev/null | jq -r 'keys[]' | grep -v '^RAILWAY_' ;;
  audit) cmd_audit ;;
  link)
    # `railway ssh -- cmd` allocates no TTY and sets no SSH_* vars, and t3's
    # pasted-code login needs both, so hand the operator an interactive shell.
    box_is_up || { echo "$BOX box is not running (run: scripts/devbox.sh --box $BOX up)" >&2; exit 1; }
    cat <<'HOWTO'
Opening a shell on the box. Run these two commands there:

  SSH_CONNECTION=headless t3 connect login --base-dir /data/t3code
      -> send the printed URL to the client; they sign in as themselves and
         read back the authorization code; paste it at the prompt
  t3 connect link --base-dir /data/t3code

Then exit and run `scripts/devbox.sh --box <box> up` so the new serve reconciles the link.
HOWTO
    exec railway ssh "${TARGET[@]}" ;;
  *) sed -n '2,26p' "$0"; exit 2 ;;
esac
