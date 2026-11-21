#!/bin/sh
# Packs mac/build/IPA Loom.app into a disk image for a release:
#
#   mac/build-app.sh && mac/make-dmg.sh
#
# The image holds the app and a shortcut to Applications, so it installs by dragging one
# onto the other. It is written to mac/build/IPA-Loom-<version>-arm64.dmg, and its SHA-256
# is printed for the release notes and the Homebrew cask. The app inside keeps the
# signature build-app.sh gave it; the image itself is not signed or notarized, so on
# another Mac the first launch needs "Open Anyway" unless it was installed with Homebrew.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
app="$here/build/IPA Loom.app"
[ -d "$app" ] || { echo "error: $app is not built yet; run mac/build-app.sh first" >&2; exit 1; }
codesign --verify --strict --deep "$app"

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
dmg="$here/build/IPA-Loom-$version-arm64.dmg"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/IPA Loom.app"
ln -s /Applications "$stage/Applications"

rm -f "$dmg"
hdiutil create -quiet -volname "IPA Loom $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"
hdiutil verify -quiet "$dmg"
(cd "$here/build" && shasum -a 256 "$(basename "$dmg")")
echo "built: $dmg"
