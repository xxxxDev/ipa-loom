#!/bin/sh
# Builds "IPA Loom.app" into mac/build/. It does not install or open it.
#
#   mac/build-app.sh
#
# The app holds the Swift window and a copy of the engine (../scripts with the files it
# builds its tools from), so it keeps working when this folder moves. It holds no account,
# model or IPA: those stay in the private data folder, the same one the terminal command
# uses. The Command Line Tools are enough; Xcode is not needed.
#
# The signature is ad hoc: it is made on this Mac for this Mac.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
cd "$here"

version=2026.11.13

if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo 'IPA Loom requires an Apple Silicon Mac.' >&2
  exit 1
fi

echo "== swift build (release)"
swift build -c release --product IPALoom
bin="$(swift build -c release --show-bin-path)/IPALoom"

app="$here/build/IPA Loom.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/engine"
# SwiftPM with the Command Line Tools records the deployment target as the SDK version,
# and macOS then draws the app the old way (no Liquid Glass). Record the real SDK.
sdk=$(xcrun --show-sdk-version)
vtool -set-build-version macos 14.0 "$sdk" -replace -output "$app/Contents/MacOS/IPALoom" "$bin" 2>/dev/null

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
 <key>CFBundleIdentifier</key><string>io.ipaloom.app</string>
 <key>CFBundleName</key><string>IPA Loom</string>
 <key>CFBundleDisplayName</key><string>IPA Loom</string>
 <key>CFBundleExecutable</key><string>IPALoom</string>
 <key>CFBundleIconFile</key><string>AppIcon</string>
 <key>CFBundlePackageType</key><string>APPL</string>
 <key>CFBundleShortVersionString</key><string>$version</string>
 <key>CFBundleVersion</key><string>1</string>
 <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
 <key>LSMinimumSystemVersion</key><string>14.0</string>
 <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
 <key>NSHighResolutionCapable</key><true/>
 <key>NSHumanReadableCopyright</key><string>Open source under the MIT License.</string>
</dict></plist>
PLIST

cp "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"

echo "== engine"
# What the terminal command runs, and what first setup builds its tools from.
for part in scripts config patches native licenses ipa-loom.command LICENSE THIRD_PARTY_NOTICES.md; do
  cp -R "$root/$part" "$app/Contents/Resources/engine/"
done
find "$app/Contents/Resources/engine" \( -name '__pycache__' -o -name '.DS_Store' \) -prune -exec rm -rf {} +

echo "== sign (ad hoc, hardened runtime)"
codesign --force --options runtime --sign - --identifier io.ipaloom.app "$app"
codesign --verify --strict --deep "$app"
echo "built: $app"
echo "Not installed or opened. To try it: open \"$app\""
