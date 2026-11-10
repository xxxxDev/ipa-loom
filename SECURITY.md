# Security and private data

## What is stored

| Data | Location / handling |
|---|---|
| Apple password and token | ipatool encrypted state under the private data root |
| Separate state-unlock key | Non-synchronizing local Keychain item, scoped to the installation |
| Enrollment model | Private data root; never included in source or CI |
| Downloaded/decrypted IPA and raw diagnostics | Private run directories; may identify an app or account |
| Run summaries | Private records; still review before sharing |
| Administrator password | Entered locally for sudo; not stored by Loom |

The default data root is `~/Library/Application Support/IPA Loom/`. An explicit `IPA_LOOM_DATA_HOME` override changes that location. File encryption and permissions do not protect a session from software that already controls your macOS account. This project provides no secure-erasure guarantee.

Source checks reject unexpected files, machine-home paths, and private-key markers. This is a bounded sanity check, not proof that all personal data or secrets have been removed. Check the actual staged blobs before committing and the exact commit before pushing; a clean working copy does not prove the index is clean. Review author metadata, history, screenshots, diffs, and final release contents manually too. Test suites and their evidence are maintained separately and must not be included in the public source.

## Sharing a problem

For ordinary bugs, provide the Loom version, macOS version/architecture, stage name, redacted error, and reproduction steps using fictional inputs where possible. Remove account names, personal paths, app identifiers/names if private, and run IDs. Do not attach the entire data directory or a raw report.

Never send Apple credentials, verification codes, Keychain contents, enrollment models, capture/license files, personalized IPAs, or raw recovery reports. A decrypted output can still contain identifying metadata; verification is not a comprehensive anonymization check or permission to redistribute an app.

## Report a vulnerability

Do not open a public issue for a security problem. Email [support@v-ax.com](mailto:support@v-ax.com) with the IPA Loom version, macOS version, a minimal reproduction, and a redacted error. Use fictional inputs where possible; never attach credentials, models, app packages, or raw diagnostics.

This address is the private reporting channel for IPA Loom. No GitHub private-advisory feature is implied to be enabled. See [operations](docs/OPERATIONS.md) for recovery, cleanup, and their limits.
