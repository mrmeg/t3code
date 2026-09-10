# Client Devbox (Railway)

Dockerfile for a client-dedicated T3 Code environment on Railway: the published
`t3` npm package running `t3 serve --base-dir /data/t3code`, with all state and
credentials under the `/data` volume so redeploys are disposable. Companion to
[infra/relay/HOW-IT-WORKS.md](../relay/HOW-IT-WORKS.md); unlike the original
hand-built `devbox` project, this one is fully reproducible from this directory.

First instance: `neurospicyos-devbox` (project `a334dbf3-e0b1-4108-b953-51dfc06f6802`,
service `devbox`, workspace "alynnblanco-mom-mode-os's Projects" — client boxes live in
the client's workspace so billing and blast radius are theirs). One client per box:
a T3 environment has no per-user boundary inside it, so anyone connected sees
every project, terminal, and credential on that box.

Which relay a client box talks to is a variable choice, not a build:

- **Official T3 Connect (default for clients).** Leave the four `T3CODE_*`
  variables unset. The client signs in at app.t3.codes with their own T3
  account and uses the store mobile app and official desktop app. Nothing of
  Matt's sits in their path.
- **Matt's relay** (`relay.mrmeg.com` / `code.mrmeg.com`). Set the four
  `T3CODE_*` variables below. Only the fork builds of the apps can see such
  an environment.

## Provision a new box

```sh
cd infra/devbox
railway init --name <client>-devbox --workspace "<client workspace>"
railway add --service devbox \
  --variables "SHELL=/usr/bin/zsh" \
  --variables "IS_SANDBOX=1" \
  --variables "TRIFORCE_ROLE=pxa"
# Only when the client should use Matt's relay instead of official T3 Connect:
#   --variables "T3CODE_RELAY_URL=https://relay.mrmeg.com" \
#   --variables "T3CODE_CLERK_PUBLISHABLE_KEY=pk_live_Y2xlcmsuY29kZS5tcm1lZy5jb20k" \
#   --variables "T3CODE_CLERK_JWT_TEMPLATE=t3-relay" \
#   --variables "T3CODE_CLERK_CLI_OAUTH_CLIENT_ID=313pgPhRdlX9tkJh"
railway service devbox
railway volume add --mount-path /data
railway up --service devbox --detach
railway redeploy   # first `up` may predate the volume attach; redeploy mounts it
```

Service variables and why each exists:

| Variable                | Purpose                                                                                                                                                                                                                                                           |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `T3CODE_*` (four)       | Optional. Point the published `t3` at relay.mrmeg.com instead of official T3 Connect (Matt's box has them; client boxes normally do not).                                                                                                                         |
| `SHELL=/usr/bin/zsh`    | T3 terminals spawn `$SHELL`. The entrypoint creates an empty `.zshrc` if missing so zsh skips its first-run wizard.                                                                                                                                               |
| `IS_SANDBOX=1`          | Claude Code refuses full-access (bypass) mode as root without it; the container runs as root.                                                                                                                                                                     |
| `EXPO_TOKEN`            | expo.dev access token so `eas build`, `eas update` and `expo start --tunnel` run non-interactively. Matt's box uses a personal token; a client box gets a token for a publish-only robot on the client's Expo account (e.g. `neurospicyos-devbox`), never Matt's. |
| `TRIFORCE_ROLE=pxa`     | Client boxes only. Read by the client project's governance hooks and skills; unset means unrestricted (Matt).                                                                                                                                                     |
| `DEVBOX_RESTART_AT_UTC` | Matt's box only: daily restart that also activates the staged CLI release.                                                                                                                                                                                        |

Set a variable later with `railway variables --set NAME=value --skip-deploys`,
then `scripts/devbox.sh up`: variables are baked into a deployment, and
`restart` reuses the old one.
From the fork checkout, `scripts/devbox.sh [--box client] up|restart|down|status|refresh|link|ssh|audit|vars`
wraps the day-to-day commands with the right project IDs and upload layout. A
new client box means one more entry in that script's `case "$BOX"` table.

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
4. `scripts/devbox.sh --box <client> link` opens a shell on the box with the
   two commands to run: `SSH_CONNECTION=headless t3 connect login --base-dir /data/t3code`
   (prints a URL; the client signs in as themselves — app.t3.codes for official
   T3 Connect, code.mrmeg.com for Matt's relay — and reads back the code, which
   you paste), then `t3 connect link --base-dir /data/t3code`. `railway ssh`
   sets no `SSH_*` variables, so without that prefix t3 would attempt the
   loopback-browser flow and hang.
5. `scripts/devbox.sh --box <client> up` so the next serve reconciles the link
   and opens the tunnel. The client then signs in and sees the environment.

## Personal box (mrmeg)

Matt's own devbox (project `devbox`, `5e74fae8-5b59-4f41-b778-f140ec224646`,
service `devbox`, workspace "mrmeg's Projects" — also hosts the relay Postgres,
which must never be taken down with it) runs this same image, but is connected
to the fork repo (`mrmeg/t3code`, branch `mrmeg`, root directory
`/infra/devbox`) instead of CLI `railway up`: pushes that touch
`infra/devbox/**` rebuild it automatically (`watchPatterns` in `railway.json`).

Daily refresh: `DEVBOX_RESTART_AT_UTC=08:00` on the service makes the container
exit at 4am ET; restart policy ALWAYS boots a fresh one, which activates the CLI
release staged by `devbox-refresh` and resets memory to baseline. No cron
service, no token.

Lifecycle (also available from the Railway dashboard / mobile app):

```sh
scripts/devbox.sh down     # stop when not working (volume and its data persist; only the volume bills)
scripts/devbox.sh up       # start again (re-uploads infra/devbox; falls back to restart when unchanged)
scripts/devbox.sh restart  # reset memory now and apply the staged CLI release, no rebuild (variable changes need `up`)
```

While the box is stopped there is no container to exit, so the daily restart
cannot revive it, and `railway redeploy` has no deployment to repeat: `down`
sticks until `up` re-uploads the image source.

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
- **Editor**: Zed (or VS Code Remote-SSH) over Tailscale SSH, so the box holds
  the only checkout and nothing needs syncing with the laptop. The laptop's
  `~/.ssh/config` aliases `railway-devbox` to the box's MagicDNS name
  (`devbox.tail02c842.ts.net`; it changes if the tailnet hostname does), and
  Zed's `ssh_connections` lists that alias. `zed ssh://railway-devbox/data/work/<repo>`
  opens a project; Zed installs its server into `/data/home/.zed_server`, which
  persists. The image rewrites root's passwd entry to `/data/home` + zsh
  because Tailscale SSH sessions start from passwd, not the image ENV.

One-time setup after the image lands:

1. `tailscale up --ssh --hostname devbox` over `railway ssh` (the printed
   auth URL enrolls the box; state persists on `/data/tailscale`).
2. `railway variables --set "EXPO_TOKEN=<token from expo.dev/settings/access-tokens>"`.
3. `gh repo clone mrmeg/agent-config "$HOME/agent-config"` on the box.

## Toolchain

An agent on the box has to find the same CLIs the same skills use on the laptop;
a missing one reads as a broken skill rather than a missing install. Three places
own a tool, and which one depends only on how it is packaged:

| Where                          | What                                                                                                     | Persistence                                                         |
| ------------------------------ | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `devbox-refresh.sh` (npm)      | t3, codex, claude, bun, pnpm, eas, ngrok, railway, supabase, stripe, clerk, sentry-cli, wrangler, vercel | `/data/cli/current` on the volume, restaged daily, promoted at boot |
| `Dockerfile` (apt + installer) | git, gh, tailscale, zsh, tini, ripgrep, fd, jq, less, tmux, uv, node/npm                                 | image only — apt installs do not survive a redeploy                 |
| `$HOME/.local/bin`             | aws, `claude-bedrock` wrapper                                                                            | volume, installed by hand                                           |

Add an npm-packaged CLI to **both** `devbox-refresh.sh` and the `npm i -g` in the
Dockerfile: the first is the live set, the second is what a fresh volume falls
back to. Anything else goes in the Dockerfile and needs a rebuild (`up`, or a
push that touches `infra/devbox/**`).

Not installed on purpose: argent and maestro (they drive simulators and physical
devices, which a Railway container has none of) and docker.

`/etc/devbox-env.sh` is the one environment definition, wired into `/etc/zsh/zshenv`
(all zsh), `/etc/profile.d/devbox.sh` (login shells) and `$BASH_ENV`
(non-interactive bash). It puts `/data/cli/current/bin` and `$HOME/.local/bin` on
PATH and sources the credential file below. A PATH entry that lives only in
`~/.zshrc` is invisible to non-interactive shells — which is the shape an agent's
Bash tool runs in — so it belongs here instead.

## Credentials

Two mechanisms, chosen by what the CLI supports:

- **Its own login state**, for anything with a headless flow: `gh auth login`,
  `railway login --browserless`, `supabase login --token`, `stripe login
--interactive`, `clerk login`, `vercel login`, `eas` (via `EXPO_TOKEN`). All of
  them write under `$HOME`, which is on the volume, so one login survives every
  redeploy. Revoke per-device from the vendor's dashboard.
- **A service variable**, for token-only CLIs and anything an agent reads from
  the environment: `SENTRY_AUTH_TOKEN`, `CLOUDFLARE_API_TOKEN`,
  `CLOUDFLARE_ACCOUNT_ID`, `EXPO_TOKEN`, `AWS_BEARER_TOKEN_BEDROCK`. Set them
  with `railway variables --set NAME=value --skip-deploys`, then `up`.

Railway variables reach PID 1, so `t3 serve` and the agents it spawns have them,
but a Tailscale SSH session starts from `/etc/passwd` with a clean environment and
does not. `entrypoint.sh` therefore mirrors an allowlist of names into
`$HOME/.config/devbox/env` (0600), which `/etc/devbox-env.sh` sources — so the
same credential is present through T3, Zed, and plain ssh alike. The file is
rewritten every boot: change the service variable, never the file. Adding a new
token means adding its name to that allowlist.

`scripts/devbox.sh audit` reports which credentials are present without printing
any of them.

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

- Update t3 / provider CLIs / bun / pnpm / eas / the service CLIs: restart the
  box. The image bakes them only as a fallback; the live set is
  `/data/cli/current` on the volume.
  `devbox-refresh` runs a minute after every boot and then daily (or on demand:
  `scripts/devbox.sh refresh`), installing the latest releases into
  `/data/cli/next`, and `entrypoint.sh` promotes that to `current` on the next
  boot. Boot therefore never waits on the npm registry, live sessions never see
  files change under them, and `/data/cli/releases` keeps the previous release
  for a manual rollback (`ln -sfn /data/cli/releases/<older> /data/cli/current`,
  then restart). `/data/cli/refresh.log` holds the last refresh output.
- `railway.json` (config as code) is deprecated by Railway in favor of
  `.railway/railway.ts`, with existing files honored until 2026-12-01. As of
  Sep 2026 `railway config migrate` emits a stub that drops the builder,
  watch-pattern and restart-policy settings into comments, so the migration is
  deferred. Before the deadline, either re-run the migration once it round-trips
  those settings or move them into the service settings in the dashboard and
  delete the file.
- Logs: Railway deploy logs (serve writes to stdout). tailscaled logs to
  `/data/tailscale/tailscaled.log`, truncated each boot.
- Known gotcha: Cloudflare Bot Fight Mode challenges Railway egress IPs —
  keep it off on the zone (HOW-IT-WORKS.md debugging map).
