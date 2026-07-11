#!/bin/sh
# Install App Store export options where Xcode Cloud's exportArchive step expects them.
# Xcode 26+ requires method "app-store-connect" (not deprecated "app-store").
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_PLIST="${SCRIPT_DIR}/app-store-exportoptions.plist"

if [ ! -f "$SOURCE_PLIST" ]; then
  echo "error: missing ${SOURCE_PLIST}"
  exit 1
fi

# Xcode Cloud uses /Volumes/workspace/ci/app-store-exportoptions.plist for App Store export.
if [ -n "${CI_WORKSPACE:-}" ]; then
  DEST_DIR="${CI_WORKSPACE}/ci"
  mkdir -p "$DEST_DIR"
  cp "$SOURCE_PLIST" "${DEST_DIR}/app-store-exportoptions.plist"
  echo "Installed App Store export options at ${DEST_DIR}/app-store-exportoptions.plist"
  plutil -p "${DEST_DIR}/app-store-exportoptions.plist"
else
  echo "CI_WORKSPACE unset; skipping Xcode Cloud export options install (local run)."
fi

exit 0
