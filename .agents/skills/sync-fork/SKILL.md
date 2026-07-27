---
name: sync-fork
description: Sync this fork with upstream pingdotgg/t3code — fast-forward main, rebase the mrmeg branch, push both, and resolve rebase conflicts if they occur.
---

# Sync fork with upstream

This repo is Matt's fork (origin=mrmeg/t3code) of upstream pingdotgg/t3code.
Layout: `main` is a pristine mirror of upstream/main; all personal changes live
on `mrmeg`. Never commit to `main`.

The Railway devbox (project `devbox`, service `devbox`) runs the published
`t3` npm package on its volume — it does NOT deploy from this repo. The sync
script updates it via `railway ssh -- npm i -g t3@latest` as its final step.

## Steps

1. Run `./scripts/sync-fork.sh` from the repo root.
2. If it succeeds, report how many upstream commits came in (`git log --oneline main@{1}..main` if available, otherwise summarize the script output) and whether the devbox `t3` update succeeded, then stop.
   - A devbox update failure is non-fatal (the script says so); report it and suggest `railway ssh -- npm i -g t3@latest` from the repo root, which is linked to the devbox project.
3. If it stops with a dirty working tree, show the user what's uncommitted and ask whether to commit it to `mrmeg` first (never to `main`).
4. If it stops on a rebase conflict:
   - Inspect the conflict; personal commits on `mrmeg` are few and focused (iOS signing env vars in `apps/mobile/app.config.ts`, plugin registrations), so prefer keeping BOTH upstream's changes and the personal customization when merging hunks.
   - After resolving: `git add <files> && git rebase --continue`, then `git push --force-with-lease origin mrmeg`.
   - If the conflict indicates upstream now natively supports something a personal commit does (e.g. they added their own bundle-ID override), drop that commit from the rebase and tell the user their patch is obsolete.
5. Confirm the final state: `git branch -vv` should show `mrmeg` tracking `origin/mrmeg` up to date, and `main` matching `upstream/main`.
