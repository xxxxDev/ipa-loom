# Changelog

## v2026.11.10

Initial public source release. The complete first-run flow on a Mac without IPA Loom installed remains independently unverified; see the README preview limitations.

### New

- **Guided first setup.** Download verified tools, sign in locally, and prepare a private enrollment model through one launcher.
- **Upstream compatibility checks.** Find new stable releases and build candidates separately without replacing installed tools.
- **Recovery and cleanup.** Recover interrupted setup and preview removal of run data or the private installation.

### Changes

- **Readable in either theme.** The logo switches between dark ink on light pages and white on dark pages in both README translations.
- **See the commands and workflow.** Dark documentation images show actual help output and a clearly labeled synthetic workflow, without private account or app data.
- **Consistent project language.** Commands, messages and project documents use English; a Traditional Chinese README is also available.
- **Clearer setup and release guidance.** Distinguish source checks from account-dependent verification and identify the complete first-run flow on a new Mac as still unverified.
- **Date releases.** Use non-padded date tags such as `v2026.11.9`.

### Fixes

- **Validate before setup.** Invalid targets and arguments stop before initialization; filename options can precede the target.
- **Accurate versions.** Newly built tools report the selected dependency version.
- **Read-only diagnostics.** Readiness checks no longer create storage or roll back setup.
- **Safer recovery.** Interrupted cleanup must resume before reuse, and working files are retained when child termination or ownership restoration is uncertain.
- **Exited tools on macOS.** Recover an already exited child when macOS refuses a second stop signal, without signalling a reused process ID or clearing an uncertain run.
- **Clear Keychain recovery.** A missing generated key no longer prompts for a passphrase the user cannot know; standalone key removal is limited to older installations with user-chosen keys.
- **Reliable output checks.** Reject incomplete verification reports and oversized inputs, and keep Unicode output names within filesystem limits.
