# Client Devbox (Railway)

Dockerfile for a client-dedicated T3 Code environment on Railway: the published
`t3` npm package running `t3 serve --base-dir /data/t3code`, with all state and
credentials under the `/data` volume so redeploys are disposable. Companion to
[infra/relay/HOW-IT-WORKS.md](../relay/HOW-IT-WORKS.md); unlike the original
hand-built `devbox` project, this one is fully reproducible from this directory.

First instance: `neurospicyos-devbox` (project `a334dbf3-e0b1-4108-b953-51dfc06f6802`,
service `devbox`, workspace "alynnblanco-mom-mode-os's Projects" — client boxes live in
the client's workspace so billing and blast radius are theirs).

## Provision a new box

```sh
cd infra/devbox
railway init --name <client>-devbox --workspace "<client workspace>"
railway add --service devbox \
  --variables "T3CODE_RELAY_URL=https://relay.mrmeg.com" \
  --variables "T3CODE_CLERK_PUBLISHABLE_KEY=pk_live_Y2xlcmsuY29kZS5tcm1lZy5jb20k" \
  --variables "T3CODE_CLERK_JWT_TEMPLATE=t3-relay" \
  --variables "T3CODE_CLERK_CLI_OAUTH_CLIENT_ID=313pgPhRdlX9tkJh"
railway service devbox
railway volume add --mount-path /data
railway up --service devbox --detach
railway redeploy   # first `up` may predate the volume attach; redeploy mounts it
```

`HOME` is `/data/home`, so `gh`, git, and provider credentials survive redeploys
alongside the t3 state in `/data/t3code`.

## One-time setup (per client, over `railway ssh`)

All commands run on the box; the client's identities, never yours:

1. `gh auth login` — client's GitHub account (device flow works headless).
2. Clone their repo under `/data` and add it as a project.
3. Provider credential — the image ships both Codex and Claude Code CLIs.
   Client-self-serve from a T3 web terminal once the box is linked:
   - Codex: `codex login --device-auth` — prints a code + URL; client signs
     into their own OpenAI account on any device. Verified available on the
     deployed image. (Alternates: `--with-api-key` / `--with-access-token`.)
   - Claude: Anthropic API key / `claude setup-token` output, as a service
     variable or in `/data/home`.
     Same goes for GitHub: `gh auth login` uses a device code, so the client can
     run it from the T3 terminal too.
4. `t3 connect login --base-dir /data/t3code` signed in as the client's Clerk
   user — forward the OAuth callback first:
   `ssh -L 34338:127.0.0.1:34338 <box>` (see HOW-IT-WORKS.md).
5. `t3 connect link --base-dir /data/t3code`, then `railway redeploy` so the
   next serve reconciles the link and opens the tunnel.

## Operations

- Update t3: `railway redeploy` rebuilds the image with `t3@latest` (layer
  cache permitting), or `railway ssh -- npm i -g t3@latest` for a quick bump.
- Logs: Railway deploy logs (serve writes to stdout).
- Known gotcha: Cloudflare Bot Fight Mode challenges Railway egress IPs —
  keep it off on the zone (HOW-IT-WORKS.md debugging map).
