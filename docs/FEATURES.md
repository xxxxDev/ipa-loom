# Features

- One launcher for first setup and routine Store-link/local-IPA workflows.
- Pinned, SHA256-checked tool downloads and an ipatool patch checksum.
- Separate temporary storage for the compiler, modules, and telemetry settings, removed after setup.
- Local interactive Apple authentication, a generated unlock key, and per-installation Keychain scope.
- App/IPA identity checks, model recovery, plaintext verification, and atomic activation.
- Staged rollback, interrupted-setup recovery, and preview-first cleanup commands.
- Metadata-based output filenames with an optional suffix.
- Stable upstream release detection, with separate temporary builds and checks before any adoption.

# Limits

- Apple Silicon macOS only; Apple developer tools require a separate system installation.
- The complete first-run login and model setup still need testing on a Mac without IPA Loom installed.
- Apple enrollment model recovery and account entitlement to the app remain necessary; arbitrary apps are not guaranteed.
- Plaintext verification does not establish trusted signing or installability.
- Building a new tool version cannot replace testing the actual workflow with authorized accounts and apps.
- Private runtime cleanup does not remove external backups, system accounts, or purchase records.
