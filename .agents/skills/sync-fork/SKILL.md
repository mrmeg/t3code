---
name: sync-fork
description: Sync this fork with upstream pingdotgg/t3code and roll the result out unattended — fast-forward main, rebase mrmeg, push, rebuild and reinstall the desktop app, build and install the mobile app on Matt's phones and tablet, update the devboxes, deploy the relay — then report what landed and which devices were unreachable.
---

# Sync fork with upstream

This repo is Matt's fork (origin=mrmeg/t3code) of upstream pingdotgg/t3code.
Layout: `main` is a pristine mirror of upstream/main; all personal changes live
on `mrmeg`. Never commit to `main`.

Human runbook for every step below, no agent needed: `FORK.md` at the repo root.

`./scripts/sync-fork.sh` does the whole job without babysitting. Only the git
steps are fatal; every rollout step records its outcome and the script ends
with a `═══ sync-fork summary` block. What it rolls out:

- **Desktop** — `/Applications/T3 Code (Alpha).app` is a local fork build, so
  the in-app updater cannot touch it. Rebuilt (`pnpm dist:desktop:dmg:arm64`)
  and swapped in when the version or any desktop-facing code changed since the
  last build; restarted unless the sync is running inside a T3 terminal.
  `T3 Code (Alpha) 2.app` is the official build and is left alone.
- **Mobile** — `eas build --profile production:device --local` for iOS and
  Android, only when `apps/mobile`, `packages`, or the lockfile changed since
  the last build (artifacts in `apps/mobile/build/`, named by commit). Installs
  onto the devices listed in `.env.local` (`SYNC_FORK_IOS_UDIDS`,
  `SYNC_FORK_ANDROID_SERIALS`) via `xcrun devicectl` and `adb`, skipping any
  device already at that commit. Needs `eas` logged in as `T3CODE_EXPO_OWNER`
  (`mrmeg`) or `EXPO_TOKEN` set; otherwise the whole mobile step is skipped
  with the reason in the summary.
- **Devboxes** — Matt's `devbox` and the client's `neurospicyos-devbox` run the
  published `t3` npm package; updated via `railway ssh -- npm i -g t3@latest`.
- **Relay** — `vp run --filter t3code-relay deploy --stage prod --yes` so
  relay.mrmeg.com and code.mrmeg.com serve the rebased branch (web build is
  memoized; cheap when nothing web-facing changed).

State (last built commit, last installed commit per device) lives in
`.t3/sync-fork.state`, gitignored. Delete a `device_<id>=` line to force a
reinstall, or delete an artifact to force a rebuild.

## Steps

1. Run `./scripts/sync-fork.sh 2>&1 | tee /tmp/sync-fork.log` from the repo
   root **in the background**. A full run with desktop and both mobile builds
   takes 20–40 minutes. Poll the log; do not sit on the foreground call.
2. When it finishes, report from the summary block:
   - upstream commits that came in (`git log --oneline main@{1}..main` if
     available, otherwise the count the script printed);
   - desktop: rebuilt / current / needs manual restart / failed;
   - mobile: which devices were **installed**, which were **already current**,
     which were **unreachable** (⚠ lines — off, asleep, off-network, or not on
     adb), and which **failed** (✖ lines — ad-hoc profile, Play Store conflict,
     build error). Name the unreachable devices explicitly so Matt knows what
     to plug in or wake before the next run;
   - devboxes and relay: updated or the manual command to run.
     Then stop. Every non-git failure is non-fatal and the summary already
     carries its manual fallback command.
3. If it stops with a dirty working tree, show what's uncommitted and ask
   whether to commit it to `mrmeg` first (never to `main`).
4. If it stops on a rebase conflict:
   - Inspect the conflict; personal commits on `mrmeg` are few and focused
     (iOS signing env vars in `apps/mobile/app.config.ts`, plugin
     registrations, the AgentActivity widget, the PR-status fix in
     `apps/server/src/sourceControl`), so prefer keeping BOTH upstream's
     changes and the personal customization when merging hunks.
   - After resolving: `git add <files> && git rebase --continue`, then
     `git push --force-with-lease origin mrmeg`, then re-run the script to
     finish the rollout steps the conflict cut short.
   - If the conflict shows upstream now natively supports something a personal
     commit does, drop that commit from the rebase and tell Matt the patch is
     obsolete.
5. Confirm the final state: `git branch -vv` should show `mrmeg` tracking
   `origin/mrmeg` up to date, and `main` matching `upstream/main`.

## Known blockers worth naming in the report

- **Android Play Store build.** The fork keeps upstream's Android package id
  (`com.t3tools.t3code`), so a Play Store install of T3 Code on the phone
  blocks the fork APK (same id, different signing key). The script detects
  this and reports it; Matt must uninstall the store app for the fork to land.
- **eas account.** If the summary says eas is logged in as someone else,
  tell Matt to `eas login` as
  `mrmeg` or export `EXPO_TOKEN`, then rerun — everything else already landed.
- **New device.** An iOS install failure on a freshly added UDID usually means
  it is not in the ad-hoc provisioning profile: `eas device:create`, delete the
  ipa in `apps/mobile/build/`, rerun.
