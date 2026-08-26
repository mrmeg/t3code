---
name: sync-fork
description: Sync this fork with upstream pingdotgg/t3code — fast-forward main, rebase the mrmeg branch, push both, and resolve rebase conflicts if they occur.
---

# Sync fork with upstream

This repo is Matt's fork (origin=mrmeg/t3code) of upstream pingdotgg/t3code.
Layout: `main` is a pristine mirror of upstream/main; all personal changes live
on `mrmeg`. Never commit to `main`.

The Railway devboxes (Matt's `devbox` project and the client's
`neurospicyos-devbox` in Alynn's workspace) run the published `t3` npm
package — they do NOT deploy from this repo. The sync script updates both via
`railway ssh -- npm i -g t3@latest`. As its final step it also redeploys the
relay stack (`vp run --filter t3code-relay deploy --stage prod --yes`) so the
relay worker and the hosted web app at code.mrmeg.com always serve the freshly
rebased branch; the web build is memoized, so this is cheap when nothing
web-facing changed.

The installed desktop app (`/Applications/T3 Code (Alpha).app`) is a local
build from this fork, so the in-app updater cannot update it. After syncing,
the script compares the installed bundle version against
`apps/desktop/package.json` and, if they differ, rebuilds
(`pnpm dist:desktop:dmg:arm64`), swaps the new bundle into `/Applications`,
and restarts the app — unless the sync is running inside a T3 terminal, in
which case it installs the bundle but leaves the restart to the user.

## Steps

1. Run `./scripts/sync-fork.sh` from the repo root. The desktop rebuild step can take several minutes.
2. If it succeeds, report how many upstream commits came in (`git log --oneline main@{1}..main` if available, otherwise summarize the script output), whether the devbox `t3` updates succeeded (both boxes), whether the desktop app was rebuilt (and if it needs a manual restart), and whether the relay deploy succeeded, then stop.
   - A devbox update failure is non-fatal (the script says so); report it and suggest `railway ssh -- npm i -g t3@latest` from the repo root, which is linked to the devbox project.
   - A desktop rebuild failure is also non-fatal; report it and suggest running `pnpm dist:desktop:dmg:arm64` manually, then reinstalling the zip from `release/`.
   - A relay deploy failure is also non-fatal; report it and suggest `vp run --filter t3code-relay deploy --stage prod --yes`.
3. If it stops with a dirty working tree, show the user what's uncommitted and ask whether to commit it to `mrmeg` first (never to `main`).
4. If it stops on a rebase conflict:
   - Inspect the conflict; personal commits on `mrmeg` are few and focused (iOS signing env vars in `apps/mobile/app.config.ts`, plugin registrations), so prefer keeping BOTH upstream's changes and the personal customization when merging hunks.
   - After resolving: `git add <files> && git rebase --continue`, then `git push --force-with-lease origin mrmeg`,
     then re-run `./scripts/sync-fork.sh` to finish the desktop, devbox, and relay steps the conflict cut short.
   - If the conflict indicates upstream now natively supports something a personal commit does (e.g. they added their own bundle-ID override), drop that commit from the rebase and tell the user their patch is obsolete.
5. Confirm the final state: `git branch -vv` should show `mrmeg` tracking `origin/mrmeg` up to date, and `main` matching `upstream/main`.
