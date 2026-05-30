#!/bin/bash
#
# build-dmg.sh — build an unsigned (ad-hoc) Release .app and package it as a DMG.
#
# This is the "Option A" pipeline: no Apple Developer account, no notarization.
# Users who download the resulting DMG will need to approve it once via
# System Settings → Privacy & Security → "Open Anyway".
#
# Usage:  ./build-dmg.sh
# Output: ./Claudicator.dmg
#
set -euo pipefail

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

# Build OUTSIDE the project root. The .xcodeproj uses a synchronized root group
# (every file under SOURCE_ROOT is a target member), so derived data left inside
# the repo gets swept back into the target and breaks the build with "Multiple
# commands produce GeneratedAssetSymbols…". Keep all output in a temp dir.
DERIVED="$(mktemp -d)/DerivedData"

echo "==> Building ${SCHEME} (Release, ad-hoc signed)…"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED}" \
  CODE_SIGN_IDENTITY="-" \
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

echo "==> Done. Attach BOTH to the GitHub release tagged v${VERSION}:"
echo "      • ${DMG}"
echo "      • ${APPCAST}"
ls -lh "${DMG}" "${APPCAST}"
