#!/bin/bash
#
# build-dmg.sh — build a self-signed Release .app and package it as a DMG.
#
# This is the "Option A" pipeline: no Apple Developer account, no notarization.
# The app is signed with a local self-signed cert (SIGN_IDENTITY below) so its
# code identity is STABLE across versions — that's what lets a granted Keychain
# "Always Allow" survive auto-updates. It is NOT Apple-notarized, so fresh
# installs still need a one-time approval via
# System Settings → Privacy & Security → "Open Anyway".
#
# Usage:
#   ./build-dmg.sh             Build + sign + write appcast.xml (no publish).
#   ./build-dmg.sh --release   …then publish a GitHub release vX.Y.Z with the
#                              DMG + appcast attached, in one step.
#
# Output: ./Claudicator.dmg, ./appcast.xml
#
set -euo pipefail

# Pass --release to publish a GitHub release after building.
RELEASE=0
[[ "${1:-}" == "--release" ]] && RELEASE=1

# Point at the full Xcode (not the Command Line Tools) without needing sudo.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

PROJECT="Claudicator.xcodeproj"
SCHEME="Claudicator"
APP_NAME="Claudicator"
DMG="${APP_NAME}.dmg"
APPCAST="appcast.xml"

# Repo whose Releases host the DMG + appcast. Per-tag asset URLs are stable, so
# a single-item appcast describing this build is all Sparkle needs to offer it.
GH_REPO="waveoff/claudicator"

# Local self-signed code-signing identity (created once in Keychain Access).
# Must be the SAME every release — that stable identity is what makes Keychain
# "Always Allow" persist across updates. Override via env if you rename it.
SIGN_IDENTITY="${SIGN_IDENTITY:-Claudicator Code Signing}"
if ! security find-identity -p codesigning | grep -q "${SIGN_IDENTITY}"; then
  echo "ERROR: signing identity '${SIGN_IDENTITY}' not found in your keychain." >&2
  echo "       Create it: Keychain Access → Certificate Assistant → Create a" >&2
  echo "       Certificate (Self Signed Root, Code Signing), named exactly that." >&2
  exit 1
fi

# Build OUTSIDE the project root. The .xcodeproj uses a synchronized root group
# (every file under SOURCE_ROOT is a target member), so derived data left inside
# the repo gets swept back into the target and breaks the build with "Multiple
# commands produce GeneratedAssetSymbols…". Keep all output in a temp dir.
DERIVED="$(mktemp -d)/DerivedData"

echo "==> Building ${SCHEME} (Release, signed: ${SIGN_IDENTITY})…"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED}" \
  CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  clean build

APP="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "${APP}" ]]; then
  echo "ERROR: build did not produce ${APP}" >&2
  exit 1
fi

echo "==> Staging disk image contents…"
STAGE="$(mktemp -d)/${APP_NAME}"
mkdir -p "${STAGE}"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"   # drag-to-install target

echo "==> Creating ${DMG}…"
rm -f "${DMG}"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGE}" \
  -ov -format UDZO \
  "${DMG}"

echo "==> Done: ${DMG}"
ls -lh "${DMG}"

# ── Sparkle: sign the DMG and emit a one-item appcast ────────────────────────
# sign_update ships inside the resolved Sparkle SPM artifact. It reads the
# EdDSA private key from your login Keychain (created once by generate_keys),
# so no key file lives in the repo. If the tool isn't found, we skip the
# appcast rather than fail — the DMG is still usable for a manual install.
echo "==> Locating Sparkle's sign_update…"
# Prefer the EdDSA tool under artifacts/…/Sparkle/bin; explicitly skip the
# deprecated DSA copy in old_dsa_scripts/ (it would sign with the wrong scheme).
SIGN_UPDATE="$(find "${DERIVED}/SourcePackages/artifacts" \
                    "${HOME}/Library/Developer/Xcode/DerivedData" \
                    -type f -name sign_update -path '*/Sparkle/bin/sign_update' \
                    2>/dev/null | head -n 1 || true)"

if [[ -z "${SIGN_UPDATE}" ]]; then
  echo "WARNING: sign_update not found — skipping appcast generation." >&2
  echo "         Add the Sparkle package in Xcode and build once, then re-run." >&2
  exit 0
fi

VERSION="$(defaults read "${APP}/Contents/Info" CFBundleShortVersionString)"
BUILD="$(defaults read "${APP}/Contents/Info" CFBundleVersion)"
MIN_OS="$(defaults read "${APP}/Contents/Info" LSMinimumSystemVersion 2>/dev/null || echo "13.0")"
DMG_URL="https://github.com/${GH_REPO}/releases/download/v${VERSION}/${DMG}"
PUB_DATE="$(LC_ALL=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")"

echo "==> Signing ${DMG} (EdDSA)…"
# Emits e.g.:  sparkle:edSignature="…" length="123456"
SIG_ATTRS="$("${SIGN_UPDATE}" "${DMG}")"

echo "==> Writing ${APPCAST}…"
cat > "${APPCAST}" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>${APP_NAME}</title>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/${GH_REPO}/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
      <enclosure url="${DMG_URL}" ${SIG_ATTRS} type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

if [[ "${RELEASE}" -eq 1 ]]; then
  TAG="v${VERSION}"
  echo "==> Publishing ${TAG} to ${GH_REPO}…"

  command -v gh >/dev/null 2>&1 || { echo "ERROR: gh (GitHub CLI) not installed." >&2; exit 1; }

  # The DMG was built from the working tree; the release tag points at the
  # pushed master HEAD. Refuse to publish if those two could disagree — that
  # would ship a binary that doesn't match the tagged source. (The DMG and
  # appcast.xml are gitignored, so they never count as "uncommitted".)
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: uncommitted changes — commit them so v${VERSION} matches the build." >&2
    exit 1
  fi
  git fetch -q origin master
  if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/master)" ]]; then
    echo "ERROR: local master differs from origin/master — push first." >&2
    exit 1
  fi
  if gh release view "${TAG}" --repo "${GH_REPO}" >/dev/null 2>&1; then
    echo "ERROR: release ${TAG} already exists. Bump the version and rebuild." >&2
    exit 1
  fi

  # Release notes = this version's section from the CHANGELOG, if present.
  NOTES="$(awk -v v="${VERSION}" '
      $0 ~ ("^## \\[" v "\\]")  { grab=1; next }
      grab && (/^## \[/ || /^---$/) { exit }
      grab                       { print }
    ' CHANGELOG.md)"
  [[ -z "${NOTES//[[:space:]]/}" ]] && NOTES="Release ${TAG}."

  # NOTE: not a pre-release — the feed URL relies on the /releases/latest/
  # redirect, which excludes pre-releases. --latest keeps the redirect valid.
  gh release create "${TAG}" \
    --repo "${GH_REPO}" \
    --target master \
    --title "${TAG}" \
    --latest \
    --notes "${NOTES}" \
    "${DMG}" "${APPCAST}"

  echo "==> Released: https://github.com/${GH_REPO}/releases/tag/${TAG}"
else
  echo "==> Done. To publish in one step:  ./build-dmg.sh --release"
  echo "    (or attach these to a GitHub release tagged v${VERSION} manually):"
  echo "      • ${DMG}"
  echo "      • ${APPCAST}"
fi
ls -lh "${DMG}" "${APPCAST}"
