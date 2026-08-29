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
     run it from the T3 terminal too (step 1 can happen there as well).
4. `t3 connect login --base-dir /data/t3code` signed in as the client's Clerk
   user — forward the OAuth callback first:
   `ssh -L 34338:127.0.0.1:34338 <box>` (see HOW-IT-WORKS.md).
5. `t3 connect link --base-dir /data/t3code`, then `railway redeploy` so the
   next serve reconciles the link and opens the tunnel.

## Personal box (mrmeg)

Matt's own devbox (project `devbox`, `5e74fae8-5b59-4f41-b778-f140ec224646`,
service `devbox`, workspace "mrmeg's Projects" — also hosts the relay Postgres,
which must never be taken down with it) runs this same image, but is connected
to the fork repo (`mrmeg/t3code`, branch `mrmeg`, root directory
`/infra/devbox`) instead of CLI `railway up`: pushes that touch
`infra/devbox/**` rebuild it automatically (`watchPatterns` in `railway.json`).

Daily refresh: `DEVBOX_RESTART_AT_UTC=08:00` on the service makes the container
exit at 4am ET; restart policy ALWAYS boots a fresh one, which reinstalls
`t3@latest` and resets memory to baseline. No cron service, no token.

Lifecycle (also available from the Railway dashboard / mobile app):

```sh
# stop when not working (volume and its data persist; only the volume bills)
railway down --project 5e74fae8-5b59-4f41-b778-f140ec224646 --service devbox -y
# start again / restart now to reset memory
railway redeploy --project 5e74fae8-5b59-4f41-b778-f140ec224646 --service devbox -y
```

While the box is stopped there is no container to exit, so the daily restart
cannot revive it — `down` sticks until the next `redeploy`.

## App dev on the personal box

The personal box doubles as a cloud dev environment for Matt's own apps
(all bun; the Expo ones build on EAS). What each layer owns:

- **Control plane**: T3 mobile/web through the relay tunnel — unchanged.
- **Data plane**: tailscale (userspace) on the box. Dev servers — Metro on
  :8081, Vite, API servers — are reached at the box's tailnet IP from any
  device on the tailnet. `expo start --tunnel` (ngrok) is the fallback for a
  device that can't join the tailnet.
- **Builds**: EAS only. The box never holds Apple/Android signing material —
  that lives in EAS-managed credentials; build-time secrets live in `eas env`.
  `EXPO_TOKEN` (an expo.dev personal access token) as a service variable keeps
  `eas` commands non-interactive.
- **Agent config**: `$HOME/agent-config` is a clone of the private
  `mrmeg/agent-config` repo; the entrypoint pulls it and runs its `apply.sh`
  on every start, so skills edited on the laptop reach the box by the next
  restart (push from the laptop with the repo's `sync-from-laptop.sh`).

One-time setup after the image lands:

1. `tailscale up --ssh --hostname devbox` over `railway ssh` (the printed
   auth URL enrolls the box; state persists on `/data/tailscale`).
2. `railway variables --set "EXPO_TOKEN=<token from expo.dev/settings/access-tokens>"`.
3. `gh repo clone mrmeg/agent-config "$HOME/agent-config"` on the box.

Onboarding a project (on demand, not in bulk):

1. `gh repo clone <repo>` under `/data`, add as a T3 project.
2. Copy the runtime `.env` over, `bun i`.
3. Expo apps: move signing to EAS-managed credentials (`eas credentials`),
   build secrets to `eas env`, and configure `expo-updates` with a `preview`
   channel.

Testing tiers for Expo apps: Metro over tailnet/tunnel for interactive dev
(dev client → `http://<tailnet-ip>:8081`), `eas update --channel preview` for
fire-and-forget JS changes on any network, EAS build → TestFlight for native
changes. Vite gotcha: reach it by tailnet IP, or add the MagicDNS name to
`server.allowedHosts` — its host check rejects unknown hostnames.

## Operations

- Update t3 / provider CLIs / bun / eas: nothing to do. `entrypoint.sh`
  reinstalls all of them on every container start, so any restart or
  `railway redeploy` lands on current releases. The Dockerfile's versions only
  set the fallback baked into the image, and Docker caches that layer
  indefinitely — do not rely on it.
- Logs: Railway deploy logs (serve writes to stdout). tailscaled logs to
  `/data/tailscale/tailscaled.log`, truncated each boot.
- Known gotcha: Cloudflare Bot Fight Mode challenges Railway egress IPs —
  keep it off on the zone (HOW-IT-WORKS.md debugging map).
