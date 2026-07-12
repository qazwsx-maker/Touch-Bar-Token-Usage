#!/bin/bash
# Builds the release binary and assembles dist/TouchBarTokenUsage.app
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
ARCH_FLAGS="${ARCH_FLAGS:---arch arm64 --arch x86_64}"
APP_NAME="TouchBarTokenUsage"
DIST="dist"

echo "==> swift build -c release ${ARCH_FLAGS}"
# shellcheck disable=SC2086
swift build -c release ${ARCH_FLAGS}
# shellcheck disable=SC2086
BIN_DIR="$(swift build -c release ${ARCH_FLAGS} --show-bin-path)"
BIN_PATH="${BIN_DIR}/${APP_NAME}"

APP="${DIST}/${APP_NAME}.app"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${APP_NAME}"
sed "s/__VERSION__/${VERSION}/g" Support/Info.plist > "${APP}/Contents/Info.plist"

if command -v iconutil >/dev/null 2>&1; then
  echo "==> generating app icon"
  if swift scripts/genicon.swift "${DIST}/AppIcon.iconset"; then
    iconutil -c icns "${DIST}/AppIcon.iconset" -o "${APP}/Contents/Resources/AppIcon.icns" \
      || echo "(iconutil failed; continuing without icon)"
  else
    echo "(icon generation failed; continuing without icon)"
  fi
fi

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "${APP}"

echo "==> built ${APP} (version ${VERSION})"
