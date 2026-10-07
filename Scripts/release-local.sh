#!/usr/bin/env bash
# release-local.sh — build, sign and notarize a BearSpark release on this Mac.
#
#   Scripts/release-local.sh 1.3.0
#
# The local counterpart of .github/workflows/release.yml, for releasing without
# an App Store Connect API key: it notarizes through a notarytool keychain
# profile made with an Apple ID and an app-specific password.
#
# 1. bumps CFBundleVersion and ChiaKeyReleaseTag in both Info.plists
# 2. builds the package with Scripts/build-release-package.sh, signed with the
#    Developer ID Application and Installer certificates and notarized
# 3. applies the updater's gate: Developer ID Installer signature + notarized
# 4. commits the bump and tags v<version>, locally only; nothing is pushed or
#    published
#
# One-time setup, if the keychain profile does not exist yet:
#   xcrun notarytool store-credentials "<NOTARY_PROFILE>" \
#     --apple-id "<id>" --team-id "<TEAMID>" --password "<app-specific-pw>"
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTARY_PROFILE="${NOTARY_PROFILE:-HareSparkNotary}"
PLISTS=(
  "ChiaKey-Source/Loaders/OSX-IMK/Takao-Info.plist"
  "ChiaKey-Source/PreferenceApplications/OSX/Info.plist"
)

die() { echo "error: $*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }

VERSION="${1:-}"
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "usage: Scripts/release-local.sh X.Y.Z"
TAG="v${VERSION}"

cd "${ROOT_DIR}"

# --------------------------- Preflight -----------------------------------
[[ -z "$(git status --porcelain)" ]] \
  || die "working tree has uncommitted changes; commit or stash them first."
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] \
  || die "releases are cut from main."
! git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null \
  || die "tag ${TAG} already exists."

identity() {
  /usr/bin/security find-identity -v -p basic \
    | /usr/bin/sed -n "s/.*\"\\(Developer ID $1: .*\\)\"/\\1/p" | head -n1
}
APP_SIGN_IDENTITY="$(identity Application)"
INSTALLER_SIGN_IDENTITY="$(identity Installer)"
[[ -n "${APP_SIGN_IDENTITY}" ]] \
  || die "no 'Developer ID Application' certificate in the keychain."
[[ -n "${INSTALLER_SIGN_IDENTITY}" ]] \
  || die "no 'Developer ID Installer' certificate in the keychain."
xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1 \
  || die "notarytool profile '${NOTARY_PROFILE}' not set up; see the header comment."

echo "Version:   ${TAG}"
echo "App:       ${APP_SIGN_IDENTITY}"
echo "Installer: ${INSTALLER_SIGN_IDENTITY}"
echo "Notary:    ${NOTARY_PROFILE}"

# --------------------------- Version bump --------------------------------
info "Setting version to ${VERSION}"
# Undo the bump if anything below fails, so a failed run leaves no trace.
committed=0
restore_plists() {
  if [[ "${committed}" == "0" ]]; then
    git checkout -- "${PLISTS[@]}"
  fi
}
trap restore_plists EXIT

for plist in "${PLISTS[@]}"; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${plist}"
  # CFBundleVersion must stay numeric; the full tag rides in its own key,
  # which installedApplicationVersion in ChiaKeyUpdateService.m prefers.
  /usr/libexec/PlistBuddy -c "Delete :ChiaKeyReleaseTag" "${plist}" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :ChiaKeyReleaseTag string ${TAG}" "${plist}"
done

# --------------------------- Build, sign, notarize -----------------------
info "Building, signing and notarizing (notarization takes a few minutes)"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY}" \
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY}" \
NOTARY_PROFILE="${NOTARY_PROFILE}" \
  Scripts/build-release-package.sh --notarize

PKG="artifacts/release/BearSpark-${VERSION}.pkg"
[[ -f "${PKG}" ]] || die "expected package not found: ${PKG}"

# --------------------------- Updater gate --------------------------------
# The same checks release.yml applies: the updater refuses anything else.
info "Checking the package the way the updater will"
signature="$(pkgutil --check-signature "${PKG}" 2>&1 || true)"
echo "${signature}"
grep -q "Developer ID Installer" <<<"${signature}" \
  || die "package is not signed with a Developer ID Installer certificate."
gatekeeper="$(/usr/sbin/spctl --assess --type install --verbose=4 "${PKG}" 2>&1 || true)"
echo "${gatekeeper}"
grep -q "Notarized Developer ID" <<<"${gatekeeper}" \
  || die "package is not notarized or was rejected by Gatekeeper."

# --------------------------- Commit and tag ------------------------------
info "Committing the version bump and tagging ${TAG}"
git commit -q -m "chore: bump version to ${VERSION}" -- "${PLISTS[@]}"
committed=1
git tag "${TAG}"

lexicon_version="$(cat artifacts/release/lexicon-version.txt 2>/dev/null || true)"
cat <<EOF

Done.
  Package: ${ROOT_DIR}/${PKG}
  SHA-256: $(shasum -a 256 "${PKG}" | awk '{print $1}')
  Lexicon: ${lexicon_version:-unknown}
  Tag:     ${TAG} (local only)

Nothing has been pushed or published. Install the package and try it first.
EOF
