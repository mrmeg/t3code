#!/bin/sh
# Stage the latest CLI set into /data/cli/next. The entrypoint promotes it to
# /data/cli/current on the next boot, so this is safe to run while `t3 serve`
# and agent sessions are live: nothing on PATH changes until the box restarts.
#
# Run by the entrypoint (once after boot, then daily) and by sync-fork over
# `railway ssh`. Exit non-zero if any package failed; the partial `next` is
# discarded at boot because .complete is only written on full success.
set -eu

CLI_ROOT=/data/cli
NEXT="$CLI_ROOT/next"
PACKAGES="t3@latest @openai/codex@latest @anthropic-ai/claude-code@latest bun@latest eas-cli@latest @expo/ngrok@latest"

rm -rf "$NEXT"
mkdir -p "$NEXT"

# --prefix keeps this install out of the live tree; npm's cache under $HOME
# (on the volume) makes repeat runs mostly a version check.
# shellcheck disable=SC2086
npm install -g --prefix "$NEXT" --no-fund --no-audit --loglevel=error $PACKAGES

for bin in t3 codex claude bun eas; do
  [ -x "$NEXT/bin/$bin" ] || { echo "devbox-refresh: $bin missing after install" >&2; exit 1; }
  printf '%s %s\n' "$bin" "$("$NEXT/bin/$bin" --version 2>/dev/null | head -1)"
done > "$NEXT/.versions"

# Skip the promotion when nothing changed, so `current` keeps its timestamp and
# the release list stays meaningful.
if [ -f "$CLI_ROOT/current/.versions" ] && cmp -s "$NEXT/.versions" "$CLI_ROOT/current/.versions"; then
  echo "devbox-refresh: already current"
  cat "$NEXT/.versions"
  rm -rf "$NEXT"
  exit 0
fi

touch "$NEXT/.complete"
echo "devbox-refresh: staged for next boot"
cat "$NEXT/.versions"
