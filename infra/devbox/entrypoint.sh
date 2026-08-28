#!/bin/sh
set -eu

mkdir -p "$HOME" /data/t3code

# t3 is baked into the image, but Docker caches that layer, so a redeploy alone
# can ship a months-old version. Reinstalling here makes every container start
# authoritative — and survives the fact that `npm i -g` writes to the container
# filesystem, not the /data volume, so a redeploy would otherwise revert any
# manual `railway ssh -- npm i -g t3@latest` bump. Runs after the mkdir above
# so npm's cache under $HOME (/data/home) exists.
# Non-fatal: a registry blip should not keep the devbox from booting.
npm i -g t3@latest || echo "warn: t3 update failed; using the version baked into the image" >&2

# DEVBOX_RESTART_AT_UTC (HH:MM, e.g. "08:00") makes the box exit daily at that
# time; restart policy ALWAYS (railway.json) then boots a fresh container, which
# reruns the t3 install above and resets memory to baseline. Unset (the client
# default), the box runs until Railway restarts it for its own reasons.
if [ -n "${DEVBOX_RESTART_AT_UTC:-}" ]; then
  now=$(date -u +%s)
  target=$(date -u -d "$DEVBOX_RESTART_AT_UTC" +%s)
  [ "$target" -le $((now + 60)) ] && target=$((target + 86400))
  exec timeout -k 30 $((target - now)) t3 serve --base-dir /data/t3code
fi

exec t3 serve --base-dir /data/t3code
