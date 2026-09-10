#!/bin/sh
# Stage the latest CLI set into /data/cli/next. The entrypoint promotes it to
# /data/cli/current on the next boot, so this is safe to run while `t3 serve`
# and agent sessions are live: nothing on PATH changes until the box restarts.
#
# Run by the entrypoint (once after boot, then daily) and by sync-fork over
# `railway ssh`. Exit non-zero if any package failed; the partial `next` is
# discarded at boot because .complete is only written on full success.
set -eu

# Every CLI here is an npm package on purpose: npm installs land on the volume
# and update themselves, where an apt package would need an image rebuild. Keep
# this list identical to the `npm i -g` in the Dockerfile, which is the fallback
# for a fresh volume. One `npm install` for the whole set, so a registry or
# postinstall failure leaves the previous release serving instead of promoting a
# half-populated one — the cost is that any single package failing defers the
# whole day's update, which /data/cli/refresh.log records.
CLI_ROOT=/data/cli
NEXT="$CLI_ROOT/next"
PACKAGES="t3@latest @openai/codex@latest @anthropic-ai/claude-code@latest \
bun@latest pnpm@latest eas-cli@latest @expo/ngrok@latest \
@railway/cli@latest supabase@latest @stripe/cli@latest clerk@latest \
@sentry/cli@latest wrangler@latest vercel@latest"

rm -rf "$NEXT"
mkdir -p "$NEXT"

# --prefix keeps this install out of the live tree; npm's cache under $HOME
# (on the volume) makes repeat runs mostly a version check.
# shellcheck disable=SC2086
npm install -g --prefix "$NEXT" --no-fund --no-audit --loglevel=error $PACKAGES

# Running each binary is the real check: several of these packages only fetch
# their platform binary in a postinstall, so a present symlink is not proof.
for bin in t3 codex claude bun pnpm eas railway supabase stripe clerk \
           sentry-cli wrangler vercel; do
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
