#!/usr/bin/env bash
set -uo pipefail

APP_NAME="BearSpark"
APP="${HOME}/Library/Input Methods/${APP_NAME}.app"
BUNDLE_ID="com.seastudio.inputmethod.BearSpark"
APP_SUPPORT_DIR="${HOME}/Library/Application Support/BearSpark"
UPDATE_LOCK="/var/tmp/com.seastudio.bearspark.config.update.lock"
TMP_BASE="${TMPDIR:-/tmp}"
UPDATE_DOWNLOAD_DIR="${TMP_BASE%/}/BearSparkUpdates"

# Named after the bundle identifiers, not the loader name; spelled out rather
# than globbed so a dev build's caches are left alone.
set_cache_dirs() {
  CACHE_DIRS=(
    "${HOME}/Library/Caches/${BUNDLE_ID}"
    "${HOME}/Library/Caches/${BUNDLE_ID}.Preferences"
    "${HOME}/Library/Caches/${BUNDLE_ID}.PhraseEditor"
    "${HOME}/Library/Caches/${BUNDLE_ID}.Updater"
  )
}
set_cache_dirs

# Written directly by the preferences app (TakaoHelper), so they are plain
# files rather than cfprefsd-managed domains.
PLIST_GLOB="${HOME}/Library/Preferences/com.seastudio.bearspark.config"

set_defaults_domains() {
  DEFAULTS_DOMAINS=(
    "${BUNDLE_ID}"
    "${BUNDLE_ID}.Preferences"
    "${BUNDLE_ID}.PhraseEditor"
    # The updater's shared suite writes here too, so removing the file alone
    # leaves cfprefsd holding values it can write back.
    com.seastudio.bearspark.config
  )
}
set_defaults_domains

PKG_IDENTIFIERS=(
  com.seastudio.inputmethod.BearSpark.component
  com.seastudio.inputmethod.BearSpark.pkg
)

PURGE=0
DRY_RUN=0
WAIT_PID=""
SHOW_COMPLETION_ALERT=0

usage() {
  cat <<EOF
Usage: Scripts/uninstall.sh [options]

Remove the per-user BearSpark installation:
  ${APP}

By default user phrases and settings are kept so a later reinstall picks
them up again.

Options:
  --purge          Also delete user phrases, lexicons, settings, and caches.
  --keep-user-data Keep user data (default).
  --app PATH       Remove this input method bundle instead, e.g. a dev
                   build's BearSparkDev.app. Must be a BearSpark*.app
                   directly in ~/Library/Input Methods.
  --wait-pid PID   Wait for PID to exit before removing files. Used when the
                   preferences app launches this script to uninstall itself.
  --show-completion-alert
                   Show a confirmation dialog after removal. Used by the
                   preferences app.
  --dry-run        Print actions without deleting anything.
  -h, --help       Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1 ;;
    --keep-user-data) PURGE=0 ;;
    --app)
      APP="${2:-}"
      shift
      ;;
    --wait-pid)
      WAIT_PID="${2:-}"
      shift
      ;;
    --show-completion-alert) SHOW_COMPLETION_ALERT=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# Only a BearSpark bundle directly inside the user's Input Methods folder may
# be named, and its Info.plist must look like ours, so neither a bad argument
# nor a doctored bundle can point the rm -rf calls below anywhere else.
refuse() {
  echo "refusing to uninstall: $1" >&2
  exit 2
}

APP="${APP%/}"
app_base="$(/usr/bin/basename -- "${APP}")"
[[ "${app_base}" =~ ^BearSpark[A-Za-z0-9]*\.app$ ]] ||
  refuse "'${APP}' is not a BearSpark input method bundle"
# Compare the real folders, with .. and symlinks resolved, not the spelling.
app_dir="$(cd -P -- "$(/usr/bin/dirname -- "${APP}")" 2>/dev/null && pwd -P)" ||
  refuse "the folder of '${APP}' does not exist"
input_methods_dir="$(cd -P -- "${HOME}/Library/Input Methods" 2>/dev/null && pwd -P)" ||
  refuse "${HOME}/Library/Input Methods does not exist"
[[ "${app_dir}" == "${input_methods_dir}" ]] ||
  refuse "'${APP}' is not directly in ${HOME}/Library/Input Methods"
APP="${app_dir}/${app_base}"
[[ -L "${APP}" ]] && refuse "'${APP}' is a symbolic link"

# The bundle names its executable and identifier; a dev build differs in both
# folder name and identifier from the release one. Both go into paths and
# commands, so they must look the way ours do.
if [[ -f "${APP}/Contents/Info.plist" ]]; then
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${APP}/Contents/Info.plist" 2>/dev/null)"
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP}/Contents/Info.plist" 2>/dev/null)"
  [[ "${identifier}" =~ ^com\.seastudio\.inputmethod\.BearSpark[A-Za-z0-9]*$ ]] ||
    refuse "unexpected bundle identifier '${identifier}'"
  [[ "${executable}" =~ ^[A-Za-z0-9_-]+$ ]] ||
    refuse "unexpected executable name '${executable}'"
  APP_NAME="${executable}"
  BUNDLE_ID="${identifier}"
  set_cache_dirs
  set_defaults_domains
fi

# pkill -f takes a regular expression; match the bundle path literally.
APP_PROCESS_PATTERN="$(printf '%s' "${APP}/Contents/" | /usr/bin/sed 's/[][\\.*^$+?(){}|]/\\&/g')"

print_command() {
  printf '+'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

run() {
  print_command "$@"
  if [[ "${DRY_RUN}" != "1" ]]; then
    "$@"
  fi
}

# Best effort throughout: a partially removed install should still end up
# removed, so individual failures never abort the script.

if [[ -n "${WAIT_PID}" ]]; then
  echo "waiting for pid ${WAIT_PID} to exit"
  for _ in $(seq 1 50); do
    kill -0 "${WAIT_PID}" 2>/dev/null || break
    sleep 0.2
  done
fi

# Take the input source out of the system list while the binary still exists.
if [[ -x "${APP}/Contents/MacOS/${APP_NAME}" ]]; then
  run "${APP}/Contents/MacOS/${APP_NAME}" uninstall || true
fi

# Same process matching as the installer's postinstall, plus anything running
# from inside the bundle (phrase editor, preferences app).
run /usr/bin/pkill -x "${APP_NAME}" || true
run /usr/bin/pkill -f "${APP_PROCESS_PATTERN}" || true

[[ -e "${APP}" ]] && run /bin/rm -rf "${APP}"

for identifier in "${PKG_IDENTIFIERS[@]}"; do
  run /usr/sbin/pkgutil --forget "${identifier}" 2>/dev/null || true
done

if [[ "${PURGE}" == "1" ]]; then
  echo "purging user data and settings"
  [[ -e "${APP_SUPPORT_DIR}" ]] && run /bin/rm -rf "${APP_SUPPORT_DIR}"
  for cache in "${CACHE_DIRS[@]}"; do
    [[ -e "${cache}" ]] && run /bin/rm -rf "${cache}"
  done
  [[ -e "${UPDATE_DOWNLOAD_DIR}" ]] && run /bin/rm -rf "${UPDATE_DOWNLOAD_DIR}"
  for plist in "${PLIST_GLOB}"*.plist; do
    [[ -e "${plist}" ]] || continue
    run /bin/rm -f "${plist}"
  done
  for domain in "${DEFAULTS_DOMAINS[@]}"; do
    run /usr/bin/defaults delete "${domain}" 2>/dev/null || true
  done
  [[ -e "${UPDATE_LOCK}" ]] && run /bin/rm -f "${UPDATE_LOCK}"
else
  echo "keeping user data in ${APP_SUPPORT_DIR}"
fi

# A system-wide install (CLI-only path) needs root to remove; just point at it.
if [[ -e "/Library/Input Methods/${APP_NAME}.app" ]]; then
  echo "note: system-wide copy found; remove it with:" >&2
  echo "  sudo rm -rf '/Library/Input Methods/${APP_NAME}.app'" >&2
fi

if [[ -e "${APP}" ]]; then
  completion_message="BearSpark could not be completely removed. Please try again."
  echo "${completion_message}" >&2
  if [[ "${SHOW_COMPLETION_ALERT}" == "1" && "${DRY_RUN}" != "1" ]]; then
    /usr/bin/osascript -e 'display dialog "熊熊注音無法完全移除，請再試一次。" with title "熊熊注音" buttons {"確定"} default button "確定" with icon caution' || true
  fi
  exit 1
fi

completion_message="BearSpark was removed successfully. Log out and back in to clear the input source cache."
echo "${completion_message}"
if [[ "${SHOW_COMPLETION_ALERT}" == "1" && "${DRY_RUN}" != "1" ]]; then
  /usr/bin/osascript -e 'display dialog "熊熊注音已成功移除。請登出再登入以清除輸入法快取。" with title "熊熊注音" buttons {"確定"} default button "確定" with icon note' || true
fi

# The preferences app runs this from a copy in the temporary directory, because
# the original lives inside the bundle being deleted. Nothing else removes that
# copy, and it must be the last thing this script does.
case "${BASH_SOURCE[0]}" in
  "${TMP_BASE%/}"/BearSpark-uninstall-*.sh)
    [[ "${DRY_RUN}" == "1" ]] || /bin/rm -f "${BASH_SOURCE[0]}"
    ;;
esac
