#!/usr/bin/env bash
# Local archive → export → App Store Connect upload for ChargeWidgetContainer.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

ARCHIVE_PATH="$ROOT_DIR/build/ChargeWidget.xcarchive"
EXPORT_DIR="$ROOT_DIR/build/exported"
EXPORT_OPTIONS="$ROOT_DIR/ExportOptions.plist"
UPLOAD_SCRIPT="$ROOT_DIR/ci_scripts/upload-ipa-transporter.sh"

if [ ! -f "$EXPORT_OPTIONS" ]; then
  echo "error: missing export options plist at $EXPORT_OPTIONS" >&2
  exit 1
fi

if [ ! -x "$UPLOAD_SCRIPT" ]; then
  echo "error: missing executable $UPLOAD_SCRIPT" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/build" "$EXPORT_DIR"

echo "==> Archiving ChargeWidgetContainer (generic/platform=iOS)"
xcodebuild archive \
  -project "$ROOT_DIR/ChargeWidget.xcodeproj" \
  -scheme ChargeWidgetContainer \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates

echo "==> Exporting IPA to $EXPORT_DIR"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

IPA_PATH="$(find "$EXPORT_DIR" -type f -name '*.ipa' | head -n 1)"
if [ -z "$IPA_PATH" ]; then
  echo "error: no .ipa found in $EXPORT_DIR" >&2
  exit 1
fi

echo "==> Uploading $(basename "$IPA_PATH") via iTMSTransporter"
"$UPLOAD_SCRIPT" "$IPA_PATH"

echo "==> Done"
