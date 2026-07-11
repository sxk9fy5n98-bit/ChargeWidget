#!/bin/sh
# Fallback: upload a locally exported ChargeWidgetContainer .ipa via iTMSTransporter
# when Xcode Cloud still refuses App Store export for the iOS stub archive.
#
# Usage:
#   ./ci_scripts/upload-ipa-transporter.sh /path/to/ChargeWidgetContainer.ipa
#
# Requires App Store Connect API key env vars:
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (path to AuthKey_XXX.p8)
set -e

IPA_PATH="${1:-}"
if [ -z "$IPA_PATH" ] || [ ! -f "$IPA_PATH" ]; then
  echo "usage: $0 /path/to/ChargeWidgetContainer.ipa" >&2
  exit 1
fi

if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ] || [ -z "${ASC_KEY_PATH:-}" ]; then
  echo "error: set ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH" >&2
  exit 1
fi

TRANSPORTER="$(xcrun --find iTMSTransporter 2>/dev/null || true)"
if [ -z "$TRANSPORTER" ]; then
  TRANSPORTER="/Applications/Xcode.app/Contents/SharedFrameworks/ContentDeliveryServices.framework/Versions/A/itms/bin/iTMSTransporter"
fi

if [ ! -x "$TRANSPORTER" ]; then
  echo "error: iTMSTransporter not found" >&2
  exit 1
fi

echo "Uploading $(basename "$IPA_PATH") via iTMSTransporter..."
"$TRANSPORTER" -m upload \
  -assetFile "$IPA_PATH" \
  -apiKey "$ASC_KEY_ID" \
  -apiIssuer "$ASC_ISSUER_ID" \
  -keyPath "$ASC_KEY_PATH" \
  -v informational

echo "Upload finished."
