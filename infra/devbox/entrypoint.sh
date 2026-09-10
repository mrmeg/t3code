#!/bin/sh
# Devbox boot. Order matters: the environment must be reachable within seconds
# of the container starting, so nothing network-bound runs before `t3 serve`.
#
#   1. Activate the CLI release that the previous boot staged (local mv, instant).
#   2. Start tailscaled (data plane for dev servers).
#   3. Sync personal agent config (bounded by a timeout).
#   4. Kick off `devbox-refresh` in the background to stage the next CLI release
#      for the next boot (repeats daily so a long-lived box always has a fresh
#      release waiting), then exec `t3 serve`.
#
# tini is PID 1 (see Dockerfile): it forwards SIGTERM to the exec'd t3 on
# redeploy and reaps whatever agent subprocesses outlive their parent.
set -eu

CLI_ROOT=/data/cli
mkdir -p "$HOME" /data/t3code /data/tailscale /data/cache/bun "$CLI_ROOT/releases"

# --- 1. Activate a staged CLI release -----------------------------------------
# devbox-refresh installs into $CLI_ROOT/next and drops .complete when every
# package landed. Promote it to a timestamped release and repoint `current`;
# PATH (Dockerfile ENV) already prefers $CLI_ROOT/current/bin over the versions
# baked into the image, which remain the fallback on a fresh volume.
if [ -f "$CLI_ROOT/next/.complete" ]; then
  release="$CLI_ROOT/releases/$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$CLI_ROOT/next" "$release"
  ln -sfn "$release" "$CLI_ROOT/current"
  # Keep the newest two releases so a bad one can be rolled back by hand.
  ls -1d "$CLI_ROOT"/releases/* 2>/dev/null | sort | head -n -2 | xargs -r rm -rf
  echo "devbox: activated CLI release $(basename "$release")"
  sed 's/^/devbox:   /' "$release/.versions" 2>/dev/null || true
else
  rm -rf "$CLI_ROOT/next"
  echo "devbox: no staged CLI release; using $(readlink "$CLI_ROOT/current" 2>/dev/null || echo 'image-baked CLIs')"
fi

# --- 2. Tailscale --------------------------------------------------------------
# Userspace networking because Railway containers have no TUN device; inbound
# tailnet connections are proxied to loopback, so even localhost-bound dev
# servers are reachable. State lives on the volume, so after one interactive
# `tailscale up` the box rejoins the tailnet on every boot. Non-fatal.
if command -v tailscaled >/dev/null 2>&1; then
  mkdir -p /var/run/tailscale
  : > /data/tailscale/tailscaled.log
  tailscaled --state=/data/tailscale/tailscaled.state \
    --socket=/var/run/tailscale/tailscaled.sock \
    --tun=userspace-networking >>/data/tailscale/tailscaled.log 2>&1 &
fi

# --- 3. Shell + agent config ---------------------------------------------------
# A missing .zshrc makes zsh run its first-time wizard inside every T3 terminal
# on a fresh (client) box; an empty file is enough to suppress it.
[ -e "$HOME/.zshrc" ] || : > "$HOME/.zshrc"

# Personal agent config (skills, agents, output styles, CLAUDE.md) is a repo
# cloned once to $HOME/agent-config; every boot pulls it and reruns its apply
# script. Bounded so a hung remote cannot delay serve. No repo means nothing to sync.
if [ -d "$HOME/agent-config/.git" ]; then
  timeout 60 git -C "$HOME/agent-config" pull --ff-only \
    || echo "warn: agent-config pull failed; using last synced copy" >&2
  [ -x "$HOME/agent-config/apply.sh" ] && "$HOME/agent-config/apply.sh"
fi

# --- 4. Stage the next CLI release in the background, then serve ---------------
# First refresh waits a minute so boot bandwidth goes to the tunnel and the
# first agent turn; then daily. Nothing on PATH changes until the next boot, so
# a redeploy mid-refresh just leaves a partial `next` that boot discards.
(
  sleep 60
  while :; do
    devbox-refresh >"$CLI_ROOT/refresh.log" 2>&1 \
      || echo "warn: devbox-refresh failed; see $CLI_ROOT/refresh.log" >&2
    sleep 86400
  done
) &

# DEVBOX_RESTART_AT_UTC (HH:MM, e.g. "08:00") makes the box exit daily at that
# time; restart policy ALWAYS (railway.json) then boots a fresh container, which
# activates whatever devbox-refresh staged and resets memory to baseline. Unset
# (the client default), the box runs until Railway restarts it for its own reasons.
if [ -n "${DEVBOX_RESTART_AT_UTC:-}" ]; then
  now=$(date -u +%s)
  target=$(date -u -d "$DEVBOX_RESTART_AT_UTC" +%s)
  [ "$target" -le $((now + 60)) ] && target=$((target + 86400))
  exec timeout -k 30 $((target - now)) t3 serve --base-dir /data/t3code
fi

exec t3 serve --base-dir /data/t3code
