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

exec t3 serve --base-dir /data/t3code
