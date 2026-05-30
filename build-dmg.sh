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

echo "==> Building ${SCHEME} (Release, ad-hoc signed)…"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  clean build

APP="build/Build/Products/Release/${APP_NAME}.app"
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
