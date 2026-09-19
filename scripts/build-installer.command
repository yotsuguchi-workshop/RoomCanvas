#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ROOMCANVAS_TEAM_ID:?Set ROOMCANVAS_TEAM_ID to your Apple development team ID. See docs/INSTALL.md.}"
if [[ ! "$ROOMCANVAS_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  print -u2 'Invalid team ID'; exit 1
fi
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/RoomCanvas-build.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
bundle_id="${ROOMCANVAS_BUNDLE_ID:-com.yotsuguchi.RoomCanvas}"
mkdir -p Installer
xcodebuild -project RoomCanvas.xcodeproj -scheme RoomCanvas -configuration Release -destination 'generic/platform=iOS' -archivePath "$build_dir/RoomCanvas.xcarchive" "DEVELOPMENT_TEAM=$ROOMCANVAS_TEAM_ID" "PRODUCT_BUNDLE_IDENTIFIER=$bundle_id" archive
cat > "$build_dir/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>method</key><string>debugging</string><key>teamID</key><string>$ROOMCANVAS_TEAM_ID</string><key>signingStyle</key><string>automatic</string></dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$build_dir/RoomCanvas.xcarchive" -exportOptionsPlist "$build_dir/ExportOptions.plist" -exportPath Installer
print "Installer: $PWD/Installer/RoomCanvas.ipa"
