#!/bin/sh
set -eu

mkdir -p "$HOME" /data/t3code /data/tailscale /data/cache/bun

# The image bakes these CLIs, but Docker caches that layer, so a redeploy
# alone can ship months-old versions. Reinstalling here makes every container
# start authoritative — and survives the fact that `npm i -g` writes to the
# container filesystem, not the /data volume, so a redeploy would otherwise
# revert any manual bump. Runs after the mkdir above so npm's cache under
# $HOME (/data/home) exists.
# Non-fatal: a registry blip should not keep the devbox from booting.
npm i -g t3@latest @openai/codex@latest @anthropic-ai/claude-code@latest \
  bun@latest eas-cli@latest @expo/ngrok@latest \
  || echo "warn: CLI refresh failed; using versions baked into the image" >&2

# Personal agent config (skills, agents, output styles, CLAUDE.md) lives in a
# repo cloned once to $HOME/agent-config; every start pulls it and reruns its
# apply script so the box tracks the laptop. No repo means nothing to sync.
if [ -d "$HOME/agent-config/.git" ]; then
  git -C "$HOME/agent-config" pull --ff-only \
    || echo "warn: agent-config pull failed; using last synced copy" >&2
  [ -x "$HOME/agent-config/apply.sh" ] && "$HOME/agent-config/apply.sh"
fi

# Tailscale is how phones reach dev servers on the box (Metro :8081, Vite,
# API servers). Userspace networking because Railway containers have no TUN
# device; inbound tailnet connections are proxied to loopback, so even
# localhost-bound dev servers are reachable. State lives on the volume, so
# after one interactive `tailscale up` the box rejoins the tailnet on every
# redeploy by itself. Non-fatal: the box must boot even if tailscale can't.
if command -v tailscaled >/dev/null 2>&1; then
  mkdir -p /var/run/tailscale
  tailscaled --state=/data/tailscale/tailscaled.state \
    --socket=/var/run/tailscale/tailscaled.sock \
    --tun=userspace-networking >/data/tailscale/tailscaled.log 2>&1 &
fi

# DEVBOX_RESTART_AT_UTC (HH:MM, e.g. "08:00") makes the box exit daily at that
# time; restart policy ALWAYS (railway.json) then boots a fresh container, which
# reruns the refresh above and resets memory to baseline. Unset (the client
# default), the box runs until Railway restarts it for its own reasons.
if [ -n "${DEVBOX_RESTART_AT_UTC:-}" ]; then
  now=$(date -u +%s)
  target=$(date -u -d "$DEVBOX_RESTART_AT_UTC" +%s)
  [ "$target" -le $((now + 60)) ] && target=$((target + 86400))
  exec timeout -k 30 $((target - now)) t3 serve --base-dir /data/t3code
fi

exec t3 serve --base-dir /data/t3code
