#!/bin/bash
set -eu
case "$0" in */*) cd -- "${0%/*}" ;; *) cd -- . ;; esac
check_suffix() {
  case "${1//[ .]/}" in '') echo 'Empty filename suffix.' >&2; exit 2 ;; esac
}
# Validate option spelling/combinations before any system installer prompt.
case "${1-}" in
  --help|-h) [ "$#" -eq 1 ] || { echo 'Use --help alone.' >&2; exit 2; }
    while IFS= read -r line; do printf '%s\n' "$line"; done < scripts/usage.txt
    exit 0 ;;
  --setup|--check-build|--doctor|--recover|--forget-keychain)
    [ "$#" -eq 1 ] || { echo 'Use this option alone.' >&2; exit 2; } ;;
  --reset|--clean-runs)
    if [ "$#" -gt 2 ] || { [ "$#" -eq 2 ] && [ "$2" != --apply ]; }; then
      echo 'Expected only optional --apply.' >&2; exit 2
    fi ;;
  *)
    _ipa_loom_target=0
    _ipa_loom_suffix=0
    _ipa_loom_has_suffix=0
    _ipa_loom_login=0
    for _ipa_loom_arg in "$@"; do
      if [ "$_ipa_loom_suffix" -eq 1 ]; then
        case "$_ipa_loom_arg" in -*) echo 'Missing --suffix value.' >&2; exit 2 ;; esac
        check_suffix "$_ipa_loom_arg"
        _ipa_loom_suffix=0; continue
      fi
      case "$_ipa_loom_arg" in
        --suffix) _ipa_loom_suffix=1; _ipa_loom_has_suffix=1 ;;
        --suffix=*) check_suffix "${_ipa_loom_arg#--suffix=}"; _ipa_loom_has_suffix=1 ;;
        --login) _ipa_loom_login=1 ;;
        -*) echo "Unknown or misplaced option: $_ipa_loom_arg" >&2; exit 2 ;;
        *) _ipa_loom_target=$((_ipa_loom_target + 1)) ;;
      esac
    done
    if [ "$_ipa_loom_login" -eq 1 ] && [ "$_ipa_loom_has_suffix" -eq 1 ] && [ "$_ipa_loom_target" -eq 0 ]; then
      echo '--suffix needs a target when used with --login.' >&2; exit 2
    fi
    if [ "$_ipa_loom_suffix" -ne 0 ] || [ "$_ipa_loom_target" -gt 1 ]; then
      echo 'Expected one target and a value after --suffix.' >&2; exit 2
    fi ;;
esac
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo 'IPA Loom requires an Apple Silicon Mac.' >&2
  exit 1
fi
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  case "${1-}" in
    --doctor|--recover|--reset|--clean-runs|--forget-keychain)
      echo 'Developer tools unavailable; maintenance did not install or change anything.' >&2; exit 1 ;;
  esac
  echo 'Install Apple Command Line Tools in the system window, then press Return.'
  echo 'Apple developer tools are a system installation; IPA Loom reset will not uninstall them.'
  echo 'Install? [y/N]'
  [ -t 0 ] || { echo 'Developer tools require an interactive Terminal.' >&2; exit 1; }
  read -r _ipa_loom_install
  case "$_ipa_loom_install" in y|Y) ;; *) exit 1 ;; esac
  /usr/bin/xcode-select --install || true
  read -r _ipa_loom_ready
fi
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo 'Developer tools are not ready. Reopen this command after installation.' >&2
  exit 1
fi
exec /usr/bin/python3 -B scripts/entry.py "$@"
