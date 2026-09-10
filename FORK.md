# mrmeg fork of T3 Code — operator runbook

Everything needed to keep this fork and its deployments current by hand, with
no agent in the loop. Start here; the linked docs hold the deeper detail.

## 1. What this fork is

- `origin` = `mrmeg/t3code`, `upstream` = `pingdotgg/t3code`.
- `main` is a pristine mirror of `upstream/main`. Never commit to it.
- `mrmeg` carries every personal change, rebased onto `main` on each sync.
  `git log --oneline main..mrmeg` lists them. Themes:
  - Mobile: bundle id / Apple team / Expo owner overrides via env, the
    `production:device` EAS profile, pinned expo-updates channel, iOS
    AgentActivity home-screen widget, Xcode pod deployment-target plugin.
  - Server: hide stale merged/closed PR status once HEAD passes the PR head.
  - Infra: self-hosted T3 Connect relay on Cloudflare + Railway Postgres
    (`infra/relay`), reproducible Railway devbox image (`infra/devbox`),
    the `sync-fork` script and skill.

## 2. Doc map

| Topic                                                        | Read                                                        |
| ------------------------------------------------------------ | ----------------------------------------------------------- |
| Sync + rollout script (this runbook automates §4)            | `scripts/sync-fork.sh`, `.agents/skills/sync-fork/SKILL.md` |
| Relay: architecture, request flow, debugging map             | `infra/relay/HOW-IT-WORKS.md`                               |
| Relay: one-time account setup, deploy, migrations            | `infra/relay/SELFHOST.md`                                   |
| Devbox image, provisioning, personal box, app-dev on the box | `infra/devbox/README.md`, `scripts/devbox.sh`               |
| Upstream remote-access docs (pairing, Tailscale, T3 Connect) | `docs/user/remote-access.md`                                |
| Upstream keeping-in-sync docs                                | `docs/user/updating.md`                                     |

## 3. Identities and IDs

Values only; secrets are named in §7.

| Thing                                           | Value                                                                                                                                                                                                 |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Relay                                           | `https://relay.mrmeg.com` (hosted web app `https://code.mrmeg.com`)                                                                                                                                   |
| Clerk JWT template / CLI OAuth client           | `t3-relay` / `313pgPhRdlX9tkJh`                                                                                                                                                                       |
| iOS bundle id (fork)                            | `com.mrmeg.code` (widget: `com.mrmeg.code.widgets`)                                                                                                                                                   |
| Android package (fork, same as upstream)        | `com.t3tools.t3code`                                                                                                                                                                                  |
| Apple team                                      | `WRC5RMB343`                                                                                                                                                                                          |
| Expo owner / project id                         | `mrmeg` / `3ea14e94-c202-48d1-bcc4-3f2a027cc4b0`                                                                                                                                                      |
| Desktop fork bundle                             | `/Applications/T3 Code (Alpha).app` (official store build sits beside it as `T3 Code (Alpha) 2.app`; both share `~/.t3`)                                                                              |
| Railway: personal devbox                        | project `5e74fae8-5b59-4f41-b778-f140ec224646`, env `dd05b42d-9f69-4165-ac94-40311d2e70eb`, service `0b64c47f-67e1-4362-9023-99171319c376` (also hosts the relay Postgres — never delete the project) |
| Railway: neurospicyos devbox (client workspace) | project `a334dbf3-e0b1-4108-b953-51dfc06f6802`, env `972de3b3-54b5-4689-8406-5c83ce04355d`, service `6da7bde1-e7bb-4f12-b4be-136d882deeec`                                                            |
| iOS devices (UDID)                              | MM iPhone 13 Pro `00008110-000248D111F1801E`, MM-XS `00008020-000921C13604002E`, iPad `00008030-0012513E0CE3C02E`                                                                                     |
| Android device                                  | Pixel 6a serial `2A271JEGR01748`                                                                                                                                                                      |

Refresh device ids with `xcrun devicectl list devices` and `adb devices -l`.

## 4. Routine update (one command)

```sh
./scripts/sync-fork.sh 2>&1 | tee /tmp/sync-fork.log
```

Requires a clean tree, `railway` logged in, `eas` logged in as `mrmeg` (or
`EXPO_TOKEN` exported). Takes 20–40 minutes when builds are needed. Only the
git steps abort the run; everything else is recorded and printed in the
`═══ sync-fork summary` block at the end:

- `✓` landed, `⚠` skipped or unreachable (device off, asleep, off-network),
  `✖` failed with the manual command to run.
- State in `.t3/sync-fork.state` (gitignored): last built commit per artifact
  and last installed commit per device. Delete a line to force that step.
- Device targets in `.env.local`: `SYNC_FORK_IOS_UDIDS`, `SYNC_FORK_ANDROID_SERIALS`.

The rest of this file is what the script does, step by step, for when it
cannot run or a step needs doing alone.

## 5. Manual procedures

### 5.1 Git sync

```sh
git fetch upstream
git fetch . upstream/main:main        # fast-forward local main without checkout
git push origin main:main
```

Rebase `mrmeg` in a throwaway worktree that leaves `.repos` unchecked-out.
Upstream renames vendored files there in ways that differ only by case
(`Sql/` vs `SQL/`), and a normal `git rebase` in this checkout fails with
"untracked working tree files would be overwritten" on the case-insensitive
Mac filesystem. Nothing on `mrmeg` touches `.repos`.

```sh
WT=$(mktemp -d)/rebase
git worktree add "$WT" -b sync-fork-rebase mrmeg --no-checkout
git -C "$WT" sparse-checkout init --no-cone
git -C "$WT" sparse-checkout set '/*' '!/.repos/'
git -C "$WT" checkout sync-fork-rebase
git -C "$WT" -c core.hooksPath=/dev/null rebase main
# on conflict: cd "$WT", fix, git add, GIT_EDITOR=true git rebase --continue; repeat
rm -rf .repos && git reset --hard sync-fork-rebase      # adopt in the main checkout
git worktree remove --force "$WT" && git branch -D sync-fork-rebase
git push --force-with-lease origin mrmeg
vp i
```

Conflict rules: keep both upstream's change and the personal one when they
overlap (usually `apps/mobile/app.config.ts`, the `gh --json` field lists in
`apps/server/src/sourceControl`, `infra/relay/src/db.ts`). For `pnpm-lock.yaml`
take upstream's copy (`git checkout --ours pnpm-lock.yaml`) and run
`pnpm install --lockfile-only --ignore-scripts` to fold the fork's deps back in.
If upstream now does what a personal commit did, drop that commit
(`git rebase --skip`). Bail out with `git -C "$WT" rebase --abort`.

### 5.2 Desktop app (macOS, arm64)

The installed fork app is a local build; the in-app updater cannot update it.

```sh
pnpm install
pnpm dist:desktop:dmg:arm64
# artifact: release/T3-Code-<version>-arm64.zip  (version from apps/desktop/package.json)
ditto -xk release/T3-Code-<version>-arm64.zip /tmp/t3-desktop
rm -rf "/Applications/T3 Code (Alpha).app"
mv "/tmp/t3-desktop/T3 Code (Alpha).app" /Applications/
open "/Applications/T3 Code (Alpha).app"
```

Quit the running fork app first, or after the swap; do not quit it from a
terminal running inside it.

### 5.3 Mobile app

Builds run locally through EAS with the `production:device` profile (internal
distribution: ad-hoc ipa, apk). They need `eas whoami` = `mrmeg`; EAS env
`production` supplies the Clerk publishable key and relay URL at build time,
and `.env.local` supplies the bundle id / team / Expo owner overrides.

```sh
cd apps/mobile
SHA=$(git rev-parse --short=9 HEAD)
eas build --profile production:device -p ios     --local --non-interactive --output build/T3Code-release-device-$SHA.ipa
eas build --profile production:device -p android --local --non-interactive --output build/T3Code-release-device-$SHA.apk
```

Install:

```sh
xcrun devicectl device install app --device <UDID> --timeout 600 apps/mobile/build/T3Code-release-device-$SHA.ipa
adb -s <serial> install -r apps/mobile/build/T3Code-release-device-$SHA.apk
```

- iOS "not reachable": device is off, locked for a long time, or not on the
  same network; plug it in over USB and retry.
- iOS install rejected: UDID missing from the ad-hoc profile. `eas device:create`,
  delete the ipa, rebuild.
- Android `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: the Play Store build is
  installed under the same package id. Uninstall it, then install the apk.
- JS-only changes can also go over the air to installed fork builds:
  `eas update --channel production` from `apps/mobile`. Native changes
  (fingerprint changed) still need a rebuild.

### 5.4 Devboxes

Both boxes run the published `t3` npm package, not this repo. `scripts/devbox.sh`
wraps every routine operation (`--box personal` is the default, `--box client`
for the neurospicyos box):

```sh
scripts/devbox.sh status            # Railway state, boot age, CLI versions, link
scripts/devbox.sh up                # start a stopped box, or ship infra/devbox changes to a running one
scripts/devbox.sh restart           # restart without rebuilding (applies a staged CLI release, not variable changes)
scripts/devbox.sh down              # stop (volume persists; only it bills)
scripts/devbox.sh refresh           # stage the latest CLI release now
scripts/devbox.sh ssh [cmd]         # shell, or one command
scripts/devbox.sh audit             # versions, auth, link, projects, processes
scripts/devbox.sh --box client vars # variable names on the client service
scripts/devbox.sh --box client link # one-time T3 Connect sign-in with the client on chat
```

Each client gets their **own box** in their own Railway workspace: a T3
environment has no per-user boundary inside it, so sharing one would expose
every project, terminal, and credential. Client boxes normally link to official
T3 Connect (no `T3CODE_*` variables), so the client signs in at app.t3.codes
and uses the store apps; nothing of Matt's is in their path.

How the box stays current: the image bakes t3, Codex, Claude Code, bun, eas-cli
and @expo/ngrok as a fallback, but the live set comes from `/data/cli/current`
on the volume. `devbox-refresh` (a minute after every boot, then daily, and on
demand via `refresh`) installs the latest releases into `/data/cli/next`; the
next boot promotes that to `current`. So a restart is what applies updates, and
boot never waits on the npm registry. `sync-fork` stages a refresh on both boxes
and leaves activation to the daily restart (Matt's box) or the next `up`.

`railway redeploy` only works while a deployment exists. After `down` there is
none, so `up` re-uploads `infra/devbox` instead; when that upload matches what
is already running Railway skips the build, and `up` falls back to `restart`.
The two services expect different archive layouts (the personal box is
repo-connected and wants `infra/devbox/Dockerfile`; the client box was created
from `infra/devbox` and wants `Dockerfile` at the root); `up` stages the right
one. Image changes ship the same way, or by pushing `infra/devbox/**` on `mrmeg`
for the personal box (`watchPatterns` in `railway.json`).

Variables are baked into a deployment, so after `railway variables --set` run
`up` (a new deployment); `restart` reuses the old environment. Variables each
box needs: `SHELL=/usr/bin/zsh`, `IS_SANDBOX=1` (Claude Code refuses
full-access mode as root without it), `EXPO_TOKEN` (EAS builds and
`expo start --tunnel`; a publish-only robot token on client boxes), and on
Matt's box the four `T3CODE_*` relay values plus `DEVBOX_RESTART_AT_UTC=08:00`.
Client boxes also carry `TRIFORCE_ROLE=pxa` for the governance skills. Details and one-time setup:
`infra/devbox/README.md`.

### 5.5 Relay + hosted web app

```sh
vp run --filter t3code-relay deploy --stage prod --yes
```

After upstream changes to `infra/relay/migrations`, apply them by hand
(migrations do not run on deploy):

```sh
cd infra/relay && pnpm migrate:railway
```

Diverged-from-upstream files to re-check after a rebase: `infra/relay/src/db.ts`,
`infra/relay/alchemy.run.ts`, `infra/relay/package.json`. Setup, accounts, and
env: `infra/relay/SELFHOST.md`. Debugging: `infra/relay/HOW-IT-WORKS.md`.

### 5.6 T3 Connect links

An environment holds one link, to one relay. Fork builds (desktop, mobile,
`t3` with the four `T3CODE_*` vars set) talk to relay.mrmeg.com; store builds
talk to relay.t3.codes. A link made against one relay is invisible to clients
of the other.

Laptop, fork desktop: Settings → Connections → T3 Connect toggle. CLI
equivalent against `~/.t3`:

```sh
npx t3@latest connect logout   # clears a stale link/login locally, even if the old relay is unreachable
npx t3@latest connect          # login + link against the relay the CLI is configured for
```

Devbox: `t3 connect login --base-dir /data/t3code` (forward the OAuth
callback first: `ssh -L 34338:127.0.0.1:34338 <box>`), then
`t3 connect link --base-dir /data/t3code`, then `railway redeploy`.

Switching a box or laptop to the official relay: unlink/logout, remove
`T3CODE_RELAY_URL`, `T3CODE_CLERK_PUBLISHABLE_KEY`, `T3CODE_CLERK_JWT_TEMPLATE`,
`T3CODE_CLERK_CLI_OAUTH_CLIENT_ID` from its environment, then login + link.

### 5.7 Pairing without T3 Connect

Works with any client build, store or fork, while the phone is on the tailnet:

```sh
npx t3 pair --tailscale      # prints a QR / URL with a one-time token
```

Scan or paste into the mobile app's Add environment. Full options:
`docs/user/remote-access.md`.

## 6. Troubleshooting

- **Store app and fork desktop app both installed.** Same bundle id, same
  `~/.t3`. Whichever launches last wins the T3 Connect link and the relay it
  points at. Run only one; delete or rename the other.
- **Official mobile app shows no environments.** The environment is linked to
  relay.mrmeg.com. Either use the fork mobile build, or relink to the official
  relay (§5.6).
- **`eas` logged in as the wrong account.** The first line of `eas whoami` is
  the user; the Accounts list below it is not. `eas login` as `mrmeg`, or
  export `EXPO_TOKEN`.
- **Desktop build fails.** `pnpm install` first; check `release/builder-debug.yml`.
- **Relay deploy fails on Cloudflare bot challenge.** Bot Fight Mode must stay
  off on the zone (`HOW-IT-WORKS.md` debugging map).

## 7. Where secrets live (names only)

| File / store                            | Holds                                                                                                                                                                                                                      |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.env` (repo root, gitignored)          | `T3CODE_RELAY_URL`, mobile + relay-client OTLP trace URL/dataset/token                                                                                                                                                     |
| `.env.local` (repo root, gitignored)    | `T3CODE_IOS_BUNDLE_ID`, `T3CODE_APPLE_TEAM_ID`, `T3CODE_EXPO_OWNER`, `T3CODE_EXPO_PROJECT_ID`, `T3CODE_CLERK_PUBLISHABLE_KEY`, `T3CODE_CLERK_JWT_TEMPLATE`, `T3CODE_CLERK_CLI_OAUTH_CLIENT_ID`, `SYNC_FORK_*` device lists |
| `infra/relay/.env` (gitignored)         | zone names, `RELAY_DATABASE_URL`, Clerk keys, APNs key, `WEB_APP_DOMAIN`                                                                                                                                                   |
| EAS project env `production`            | build-time public config for the mobile app                                                                                                                                                                                |
| Railway service variables (each devbox) | the four `T3CODE_*` relay/Clerk vars, `EXPO_TOKEN`, `DEVBOX_RESTART_AT_UTC`                                                                                                                                                |
| `~/.t3/userdata/secrets/`               | the laptop's live T3 Connect link (`cloud-relay-url`, tokens); read-only, managed by the app                                                                                                                               |

Losing `.env.local` or `infra/relay/.env` means recreating them from the
tables above and the provider dashboards (Clerk, Cloudflare, Railway, Apple).
