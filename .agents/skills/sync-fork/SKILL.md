---
name: sync-fork
description: Sync this fork with upstream pingdotgg/t3code — fast-forward main, rebase the mrmeg branch, push both, and resolve rebase conflicts if they occur.
---

# Sync fork with upstream

This repo is Matt's fork (origin=mrmeg/t3code) of upstream pingdotgg/t3code.
Layout: `main` is a pristine mirror of upstream/main; all personal changes live
on `mrmeg`, which Railway deploys from. Never commit to `main`.

## Steps

1. Run `./scripts/sync-fork.sh` from the repo root.
2. If it succeeds, report how many upstream commits came in (`git log --oneline main@{1}..main` if available, otherwise summarize the script output) and stop.
3. If it stops with a dirty working tree, show the user what's uncommitted and ask whether to commit it to `mrmeg` first (never to `main`).
4. If it stops on a rebase conflict:
   - Inspect the conflict; personal commits on `mrmeg` are few and focused (iOS signing env vars in `apps/mobile/app.config.ts`, plugin registrations), so prefer keeping BOTH upstream's changes and the personal customization when merging hunks.
   - After resolving: `git add <files> && git rebase --continue`, then `git push --force-with-lease origin mrmeg`.
   - If the conflict indicates upstream now natively supports something a personal commit does (e.g. they added their own bundle-ID override), drop that commit from the rebase and tell the user their patch is obsolete.
5. Confirm the final state: `git branch -vv` should show `mrmeg` tracking `origin/mrmeg` up to date, and `main` matching `upstream/main`.
