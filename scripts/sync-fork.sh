#!/usr/bin/env bash
# Personal fork maintenance (mrmeg): pull latest pingdotgg/t3code into main,
# rebase the mrmeg branch on top, push both to the fork, then roll the result
# out everywhere it runs: the installed desktop app, the phones and tablets
# listed in .env.local, the Railway devboxes, and the relay stack.
#
# Safe to run any time from anywhere in the repo, unattended:
#   ./scripts/sync-fork.sh
#
# Only the git steps are fatal. Every rollout step records its outcome and the
# script ends with a summary so a single glance shows what landed, what was
# skipped, and which devices were not reachable.
#
# Device targets live in .env.local (gitignored):
#   SYNC_FORK_IOS_UDIDS="<udid> <udid> ..."        # xcrun devicectl list devices
#   SYNC_FORK_ANDROID_SERIALS="<serial> ..."       # adb devices -l (substring match)
# Unset means: the primary iPhone for iOS, every attached adb device for Android.
set -euo pipefail

WORK_BRANCH="mrmeg"
APP_NAME="T3 Code (Alpha)"
APP_PATH="/Applications/${APP_NAME}.app"
ANDROID_PACKAGE="com.t3tools.t3code"
DEFAULT_IOS_UDIDS="00008110-000248D111F1801E"
cd "$(git rev-parse --show-toplevel)"
REPO_ROOT="$PWD"
STATE_FILE="${REPO_ROOT}/.t3/sync-fork.state"
MOBILE_DIR="${REPO_ROOT}/apps/mobile"
MOBILE_BUILD_DIR="${MOBILE_DIR}/build"
# Paths whose changes require a rebuild of each artifact.
DESKTOP_PATHS=(apps/desktop apps/web apps/server packages pnpm-lock.yaml)
MOBILE_PATHS=(apps/mobile packages pnpm-lock.yaml)

SUMMARY=()
note() {
  SUMMARY+=("$1")
  echo "$1"
}

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

# Key=value state of what was last built and where it was installed, so reruns
# skip work that already landed and only touch devices that are behind.
state_get() {
  [[ -f "$STATE_FILE" ]] || return 0
  grep -E "^$1=" "$STATE_FILE" | tail -1 | cut -d= -f2- || true
}
state_set() {
  mkdir -p "$(dirname "$STATE_FILE")"
  {
    [[ -f "$STATE_FILE" ]] && { grep -vE "^$1=" "$STATE_FILE" || true; }
    echo "$1=$2"
  } >"${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

env_local_get() {
  [[ -f .env.local ]] || return 0
  grep -E "^$1=" .env.local | tail -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' || true
}

# True when the given paths differ between a recorded commit and HEAD, or when
# there is no usable recorded commit at all.
changed_since() {
  local sha="$1"
  shift
  [[ -n "$sha" ]] && git cat-file -e "$sha" 2>/dev/null || return 0
  ! git diff --quiet "$sha" HEAD -- "$@"
}

# ---------------------------------------------------------------------------
# Desktop
# ---------------------------------------------------------------------------

# Rebuild and reinstall the desktop app when the installed bundle is behind the
# repo, either by version or because desktop-facing code changed since the
# last build.
update_desktop_app() {
  [[ "$(uname)" == "Darwin" ]] || return 0

  local version installed last
  version="$(node -p "require('./apps/desktop/package.json').version")"
  installed="$(defaults read "${APP_PATH}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "none")"
  last="$(state_get desktop_built)"
  if [[ "$installed" == "$version" ]] && ! changed_since "$last" "${DESKTOP_PATHS[@]}"; then
    note "✓ Desktop: already current (${version})."
    return 0
  fi

  echo "→ Rebuilding desktop app (installed ${installed} → ${version} @ $(git rev-parse --short HEAD))..."
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
  state_set desktop_built "$(git rev-parse HEAD)"

  # If this script is itself running inside the app (a T3 terminal), quitting
  # the app would kill the sync — leave the restart to the user in that case.
  local pid=$$ cmd
  while [[ "$pid" -gt 1 ]]; do
    cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
    if [[ "$cmd" == *"${APP_NAME}.app"* ]]; then
      note "⚠ Desktop: ${version} installed; restart ${APP_NAME} yourself (sync ran inside it)."
      return 0
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || echo 1)"
    [[ -n "$pid" ]] || break
  done

  # Match the fork bundle by its exact path as a fixed string: the official
  # build shares the same bundle id and a near-identical name, and the
  # parentheses in the path would be regex groups to pgrep.
  if fork_app_running; then
    echo "→ Restarting ${APP_NAME}..."
    osascript -e "tell application \"${APP_PATH}\" to quit" || true
    for _ in $(seq 1 20); do
      fork_app_running || break
      sleep 0.5
    done
    open "$APP_PATH"
    note "✓ Desktop: updated to ${version} and restarted."
  else
    note "✓ Desktop: updated to ${version} (was not running)."
  fi
}

fork_app_running() {
  # No `grep -q`: it exits on first match, and the SIGPIPE that kills `ps`
  # makes the pipeline fail under `set -o pipefail`, reporting "not running"
  # for an app that is running.
  [[ -n "$(ps -axo command= | grep -F -- "${APP_PATH}/Contents/MacOS/")" ]]
}

# ---------------------------------------------------------------------------
# Mobile
# ---------------------------------------------------------------------------

MOBILE_SKIP_REASON=""
mobile_precheck() {
  if ! command -v eas >/dev/null 2>&1; then
    MOBILE_SKIP_REASON="eas-cli not installed"
    return 1
  fi
  local expected actual
  expected="$(env_local_get T3CODE_EXPO_OWNER)"
  # First stdout line is the signed-in user; the "Accounts:" list that follows
  # names every organization the user belongs to, which is not the login.
  actual="$(eas whoami 2>/dev/null | head -1 | tr -d '[:space:]')"
  if [[ -z "$actual" ]]; then
    MOBILE_SKIP_REASON="eas is not logged in (run 'eas login' or set EXPO_TOKEN)"
    return 1
  fi
  if [[ -n "$expected" && "$actual" != "$expected" ]]; then
    MOBILE_SKIP_REASON="eas is logged in as '${actual}', expected '${expected}' (run 'eas login' or set EXPO_TOKEN)"
    return 1
  fi
  return 0
}

# Builds the release device artifact for one platform unless the current or a
# still-valid earlier one exists. Sets MOBILE_ARTIFACT to the path on success.
MOBILE_ARTIFACT=""
build_mobile() {
  local platform="$1" ext="$2"
  local sha last artifact
  sha="$(git rev-parse --short=9 HEAD)"
  artifact="${MOBILE_BUILD_DIR}/T3Code-release-device-${sha}.${ext}"
  MOBILE_ARTIFACT=""

  if [[ -f "$artifact" ]]; then
    echo "✓ Mobile ${platform}: artifact for ${sha} already built."
    MOBILE_ARTIFACT="$artifact"
    return 0
  fi
  last="$(state_get "mobile_${platform}_built")"
  if [[ -n "$last" && -f "${MOBILE_BUILD_DIR}/T3Code-release-device-${last}.${ext}" ]] \
    && ! changed_since "$last" "${MOBILE_PATHS[@]}"; then
    echo "✓ Mobile ${platform}: no mobile changes since ${last}; reusing that build."
    MOBILE_ARTIFACT="${MOBILE_BUILD_DIR}/T3Code-release-device-${last}.${ext}"
    return 0
  fi

  echo "→ Building ${platform} release device artifact (${sha})..."
  mkdir -p "$MOBILE_BUILD_DIR"
  if (cd "$MOBILE_DIR" && eas build --profile production:device -p "$platform" --local --non-interactive --output "$artifact"); then
    state_set "mobile_${platform}_built" "$sha"
    MOBILE_ARTIFACT="$artifact"
    return 0
  fi
  return 1
}

artifact_sha() {
  local base
  base="$(basename "$1")"
  base="${base#T3Code-release-device-}"
  echo "${base%.*}"
}

install_ios() {
  local udid="$1" artifact="$2"
  local sha key name details
  sha="$(artifact_sha "$artifact")"
  key="device_${udid}"
  details="$(mktemp)"
  if ! xcrun devicectl device info details --device "$udid" --timeout 20 --json-output "$details" >/dev/null 2>&1; then
    rm -f "$details"
    note "⚠ iOS ${udid}: not reachable (off, asleep, or not on this network); skipped."
    return 0
  fi
  name="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['result']['deviceProperties']['name'])" "$details" 2>/dev/null || echo "$udid")"
  rm -f "$details"

  if [[ "$(state_get "$key")" == "$sha" ]]; then
    note "✓ iOS ${name}: already at ${sha}."
    return 0
  fi
  echo "→ Installing ${sha} on ${name}..."
  local log
  log="$(mktemp)"
  if xcrun devicectl device install app --device "$udid" --timeout 600 "$artifact" 2>&1 | tee "$log"; then
    rm -f "$log"
    state_set "$key" "$sha"
    note "✓ iOS ${name}: installed ${sha}."
    return 0
  fi
  # devicectl reports several very different problems the same way, so name the
  # one that actually happened instead of guessing at provisioning every time.
  if grep -q -e "still locked" -e "not been unlocked" "$log"; then
    note "⚠ iOS ${name}: locked; unlock the screen and rerun."
  elif grep -q -e "ineligible" -e "provisioning" -e "not.*eligible" "$log"; then
    note "✖ iOS ${name}: not in the ad-hoc profile; run 'eas device:create', delete the ipa in apps/mobile/build/, and rerun."
  else
    note "✖ iOS ${name}: install failed; see the devicectl output above."
  fi
  rm -f "$log"
}

install_android() {
  local match="$1" artifact="$2"
  local sha key serial installer
  sha="$(artifact_sha "$artifact")"
  key="device_${match}"
  serial="$(adb devices -l 2>/dev/null | awk -v m="$match" 'NR>1 && index($1,m)>0 && $2=="device" {print $1; exit}')"
  if [[ -z "$serial" ]]; then
    note "⚠ Android ${match}: not connected to adb; skipped."
    return 0
  fi

  if [[ "$(state_get "$key")" == "$sha" ]]; then
    note "✓ Android ${match}: already at ${sha}."
    return 0
  fi
  # The fork keeps upstream's Android package id, so a Play Store install of
  # T3 Code blocks it: same id, different signing key.
  installer="$(adb -s "$serial" shell dumpsys package "$ANDROID_PACKAGE" 2>/dev/null | awk -F= '/installerPackageName/ {print $2; exit}' | tr -d '\r ')"
  if [[ "$installer" == "com.android.vending" ]]; then
    note "✖ Android ${match}: Play Store T3 Code is installed under ${ANDROID_PACKAGE}; uninstall it before the fork build can install."
    return 0
  fi
  echo "→ Installing ${sha} on ${serial}..."
  if adb -s "$serial" install -r "$artifact"; then
    state_set "$key" "$sha"
    note "✓ Android ${match}: installed ${sha}."
  else
    note "✖ Android ${match}: adb install failed."
  fi
}

update_mobile() {
  local ios_udids android_serials
  ios_udids="$(env_local_get SYNC_FORK_IOS_UDIDS)"
  android_serials="$(env_local_get SYNC_FORK_ANDROID_SERIALS)"
  [[ -n "$ios_udids" ]] || ios_udids="$DEFAULT_IOS_UDIDS"
  [[ "$(uname)" == "Darwin" ]] || ios_udids=""
  if [[ -z "$android_serials" ]] && command -v adb >/dev/null 2>&1; then
    android_serials="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1}' | tr '\n' ' ')"
  fi

  if ! mobile_precheck; then
    note "⚠ Mobile: skipped (${MOBILE_SKIP_REASON})."
    return 0
  fi

  if [[ -n "$ios_udids" ]]; then
    if build_mobile ios ipa; then
      for udid in $ios_udids; do install_ios "$udid" "$MOBILE_ARTIFACT"; done
    else
      note "✖ Mobile iOS: build failed; run 'pnpm --filter @t3tools/mobile ios:release:device' to see why."
    fi
  fi

  if [[ -n "$android_serials" ]]; then
    if build_mobile android apk; then
      for serial in $android_serials; do install_android "$serial" "$MOBILE_ARTIFACT"; done
    else
      note "✖ Mobile Android: build failed; run 'eas build --profile production:device -p android --local' in apps/mobile to see why."
    fi
  elif command -v adb >/dev/null 2>&1; then
    note "⚠ Android: no devices attached to adb; skipped."
  fi
}

# ---------------------------------------------------------------------------
# Git sync (fatal on failure)
# ---------------------------------------------------------------------------

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

# The steps after the rebase build and deploy from the work branch, so land on
# it whether or not there was anything to rebase.
git checkout "$WORK_BRANCH"

behind_count="$(git rev-list --count "${WORK_BRANCH}..main")"
if [[ "$behind_count" -eq 0 ]]; then
  echo "✓ ${WORK_BRANCH} is already up to date with upstream."
  note "✓ Git: ${WORK_BRANCH} already current with upstream."
else
  echo "→ Rebasing ${WORK_BRANCH} onto main (${behind_count} new upstream commits)..."
  # The rebase runs in a throwaway worktree that leaves .repos unchecked-out.
  # Upstream renames vendored files there in ways that differ only by case
  # (Sql/ → SQL/), and a checkout that has to pass through both spellings
  # fails on this case-insensitive filesystem. Nothing on this branch touches
  # .repos, so excluding it from the rebase worktree loses nothing.
  REBASE_WT="$(mktemp -d)/rebase"
  REBASE_BRANCH="sync-fork-rebase"
  git branch -D "$REBASE_BRANCH" >/dev/null 2>&1 || true
  git worktree add -q "$REBASE_WT" -b "$REBASE_BRANCH" "$WORK_BRANCH" --no-checkout
  git -C "$REBASE_WT" sparse-checkout init --no-cone
  git -C "$REBASE_WT" sparse-checkout set '/*' '!/.repos/'
  git -C "$REBASE_WT" checkout -q "$REBASE_BRANCH"
  if ! git -C "$REBASE_WT" -c core.hooksPath=/dev/null rebase main; then
    cat <<EOF

✖ Rebase conflict. Your changes overlap with new upstream commits.
  The rebase is paused in a separate worktree: ${REBASE_WT}
  1. cd "${REBASE_WT}" and fix the conflicted files (git status)
  2. git add <files> && GIT_EDITOR=true git rebase --continue   (repeat until done)
  3. Back in this repo:
       rm -rf .repos && git reset --hard ${REBASE_BRANCH}
       git worktree remove --force "${REBASE_WT}" && git branch -D ${REBASE_BRANCH}
  4. Re-run this script; it will push and finish the rollout steps
  Or bail out with: git -C "${REBASE_WT}" rebase --abort; git worktree remove --force "${REBASE_WT}"; git branch -D ${REBASE_BRANCH}
EOF
    exit 1
  fi

  # Adopt the rebased history here. Dropping .repos first lets the reset lay
  # down the new spelling without tripping over the old one.
  rm -rf .repos
  git reset -q --hard "$REBASE_BRANCH"
  git worktree remove --force "$REBASE_WT"
  git branch -q -D "$REBASE_BRANCH"
  note "✓ Git: rebased ${WORK_BRANCH} onto ${behind_count} new upstream commits."
fi

# Push whenever the local branch differs from the fork, including a rebase that
# was finished by hand after a conflict stopped a previous run.
if [[ "$(git rev-parse "$WORK_BRANCH")" != "$(git rev-parse "origin/${WORK_BRANCH}" 2>/dev/null)" ]]; then
  echo "→ Pushing ${WORK_BRANCH} to fork..."
  git push --force-with-lease origin "$WORK_BRANCH"
  note "✓ Git: pushed ${WORK_BRANCH} to origin."
fi

# ---------------------------------------------------------------------------
# Rollout (each step non-fatal; outcomes collected in the summary)
# ---------------------------------------------------------------------------
# Everything below runs even when the branch was already up to date: a previous
# sync may have stopped on a conflict before reaching it, and the devboxes and
# relay drift on their own schedule regardless of what upstream did.

update_desktop_app || note "✖ Desktop: rebuild failed; run 'pnpm dist:desktop:dmg:arm64' manually."

update_mobile

# The Railway devboxes run the published npm package (not this repo). Stage the
# latest CLI release on each; the box activates it at its next restart (daily on
# Matt's box, next `scripts/devbox.sh up` on the client box), so live sessions
# are never disturbed. devbox.sh refuses when the box is stopped, which a raw
# `railway ssh` would not: with no container it lands on Railway's account
# endpoint and exits 0. See infra/devbox/entrypoint.sh.
echo "→ Staging t3 + provider CLI refresh on the Railway devbox..."
if "${REPO_ROOT}/scripts/devbox.sh" refresh; then
  note "✓ Devbox (mrmeg): CLI release staged; activates at the daily restart."
else
  note "⚠ Devbox (mrmeg): refresh skipped (stopped, offline, or railway not logged in); run 'scripts/devbox.sh refresh' once it is up."
fi

echo "→ Staging t3 + provider CLI refresh on the neurospicyos devbox..."
if "${REPO_ROOT}/scripts/devbox.sh" --box client refresh; then
  note "✓ Devbox (neurospicyos): CLI release staged; activates at its next 'scripts/devbox.sh --box client up'."
else
  note "⚠ Devbox (neurospicyos): refresh skipped (stopped, offline, or railway not logged in); run 'scripts/devbox.sh --box client refresh' once it is up."
fi

# Keep the deployed relay + hosted web app (relay.mrmeg.com / code.mrmeg.com)
# in step with the rebased branch. Alchemy memoizes the web build, so this is
# cheap when nothing web-facing changed.
echo "→ Deploying relay + hosted web app..."
if vp run --filter t3code-relay deploy --stage prod --yes; then
  note "✓ Relay: deployed (relay.mrmeg.com, code.mrmeg.com)."
else
  note "⚠ Relay: deploy failed; run 'vp run --filter t3code-relay deploy --stage prod --yes'."
fi

echo
echo "═══ sync-fork summary ($(git rev-parse --short HEAD) on ${WORK_BRANCH})"
printf '%s\n' "${SUMMARY[@]}"
