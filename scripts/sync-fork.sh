#!/usr/bin/env bash
# Personal fork maintenance (mrmeg): pull latest pingdotgg/t3code into main,
# rebase the mrmeg branch on top, and push both to the fork.
#
# Safe to run any time from anywhere in the repo:
#   ./scripts/sync-fork.sh
#
# If the rebase hits a conflict, the script stops and tells you what to do.
set -euo pipefail

WORK_BRANCH="mrmeg"
cd "$(git rev-parse --show-toplevel)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "✖ Working tree has uncommitted changes. Commit or stash them first:"
  git status --short
  exit 1
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"

echo "→ Fetching upstream (pingdotgg/t3code)..."
git fetch upstream

echo "→ Fast-forwarding main to upstream/main..."
if [[ "$current_branch" == "main" ]]; then
  git merge --ff-only upstream/main
else
  # Updates the local main ref without checking it out; fails if not a fast-forward.
  git fetch . upstream/main:main
fi

echo "→ Pushing main to fork..."
git push origin main:main

behind_count="$(git rev-list --count "${WORK_BRANCH}..main")"
if [[ "$behind_count" -eq 0 ]]; then
  echo "✓ ${WORK_BRANCH} is already up to date with upstream. Nothing to do."
  exit 0
fi

echo "→ Rebasing ${WORK_BRANCH} onto main (${behind_count} new upstream commits)..."
git checkout "$WORK_BRANCH"
if ! git rebase main; then
  cat <<'EOF'

✖ Rebase conflict. Your changes overlap with new upstream commits.
  1. Fix the conflicted files listed above (usually apps/mobile/app.config.ts)
  2. git add <files> && git rebase --continue
  3. git push --force-with-lease origin mrmeg
  Or bail out completely with: git rebase --abort
EOF
  exit 1
fi

echo "→ Pushing ${WORK_BRANCH} to fork..."
git push --force-with-lease origin "$WORK_BRANCH"

echo "✓ Done. main mirrors upstream, ${WORK_BRANCH} is rebased and pushed."

# The Railway devbox runs the published npm package (not this repo), so pull
# its update alongside the fork sync. Non-fatal: the fork sync already succeeded.
echo "→ Updating t3 on the Railway devbox..."
if railway ssh \
    --project 5e74fae8-5b59-4f41-b778-f140ec224646 \
    --environment dd05b42d-9f69-4165-ac94-40311d2e70eb \
    --service 0b64c47f-67e1-4362-9023-99171319c376 \
    -- npm i -g t3@latest; then
  echo "✓ Devbox t3 updated to latest."
else
  echo "⚠ Devbox update failed (offline or CLI not logged in?). Run manually:"
  echo "  railway ssh -- npm i -g t3@latest"
fi
