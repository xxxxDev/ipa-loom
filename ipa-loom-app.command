#!/bin/bash
# Builds the IPA Loom Mac app from this folder and opens it.
set -eu
case "$0" in */*) cd -- "${0%/*}" ;; *) cd -- . ;; esac
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo 'Apple Command Line Tools are needed to build the app.' >&2
  echo 'Run ./ipa-loom.command once: it offers to install them.' >&2
  exit 1
fi
mac/build-app.sh
/usr/bin/open "mac/build/IPA Loom.app"
