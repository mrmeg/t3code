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
APP_NAME="T3 Code (Alpha)"
APP_PATH="/Applications/${APP_NAME}.app"
cd "$(git rev-parse --show-toplevel)"

# Rebuild and reinstall the desktop app if the installed bundle no longer
# matches the version in the repo. Runs even when the branch was already
# up to date, since a previous sync may have skipped the rebuild.
update_desktop_app() {
  [[ "$(uname)" == "Darwin" ]] || return 0

  local version installed
  version="$(node -p "require('./apps/desktop/package.json').version")"
  installed="$(defaults read "${APP_PATH}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "none")"
  if [[ "$installed" == "$version" ]]; then
    echo "✓ Desktop app already at ${version}."
    return 0
  fi

  echo "→ Rebuilding desktop app (installed ${installed} → ${version})..."
  pnpm install || return 1
  pnpm dist:desktop:dmg:arm64 || return 1

  local zip="release/T3-Code-${version}-arm64.zip"
  if [[ ! -f "$zip" ]]; then
    echo "✖ Expected artifact ${zip} not found after build."
    return 1
  fi

  # Swap the bundle in before quitting the running instance: the old app
  # keeps working from open file handles, and if anything dies mid-restart
  # the new version is already installed.
  echo "→ Installing ${zip} to ${APP_PATH}..."
  local staging
  staging="$(mktemp -d)"
  ditto -xk "$zip" "$staging" || return 1
  rm -rf "$APP_PATH"
  mv "${staging}/${APP_NAME}.app" "$APP_PATH"
  rm -rf "$staging"

  # If this script is itself running inside the app (a T3 terminal), quitting
  # the app would kill the sync — leave the restart to the user in that case.
  local pid=$$ cmd
  while [[ "$pid" -gt 1 ]]; do
    cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
    if [[ "$cmd" == *"${APP_NAME}.app"* ]]; then
      echo "⚠ Running inside ${APP_NAME}; restart it yourself to pick up ${version}."
      return 0
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || echo 1)"
    [[ -n "$pid" ]] || break
  done

  local pgrep_pattern="T3 Code .Alpha..app/Contents/MacOS"
  if pgrep -qf "$pgrep_pattern"; then
    echo "→ Restarting ${APP_NAME}..."
    osascript -e "tell application \"${APP_NAME}\" to quit" || true
    for _ in $(seq 1 20); do
      pgrep -qf "$pgrep_pattern" || break
      sleep 0.5
    done
    open "$APP_PATH"
  fi
  echo "✓ Desktop app updated to ${version}."
}

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
  echo "✓ ${WORK_BRANCH} is already up to date with upstream."
  update_desktop_app || echo "⚠ Desktop app update failed; run 'pnpm dist:desktop:dmg:arm64' manually."
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

# Keep the installed desktop app in step with the freshly synced source.
# Non-fatal: the fork sync already succeeded.
update_desktop_app || echo "⚠ Desktop app update failed; run 'pnpm dist:desktop:dmg:arm64' manually."

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
