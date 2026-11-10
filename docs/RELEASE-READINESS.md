# Release readiness

IPA Loom remains a preview. The core workflow has been tested in an already configured local environment, but the complete first-run experience still needs independent testing. These documents do not mean a repository, release, or scheduled workflow has been published.

## What is implemented

- An explicit public-source inventory, including vector logos and two manually reviewed, hash-pinned documentation images; runtime, personal preferences, and private validation evidence stay outside the checkout.
- A first-run wizard with pinned downloads, build/CLI checks, local account/model initialization, scoped Keychain storage, and atomic activation.
- Rollback and recovery for incomplete setup, cleanup previews, and saved reset progress so interrupted removal can be retried.
- Stable upstream release detection, separate temporary builds of new versions, and a scheduled workflow definition with read-only repository permissions.
- Public source-inventory and syntax checks, with push/PR checks and tag-format validation; the test suite is maintained privately outside the source repository.
- A consistent `ipa-loom.command` entry point, argument validation before initialization, and build-version labels derived from the selected dependency.
- An English project with a paired Traditional Chinese README, upstream license notices, and non-padded date-tag validation.

## What remains before a general release

- Independently test the complete first-run flow on a Mac without IPA Loom installed: Apple login, model setup, and decryption. Building tools alone does not validate this flow.
- When adopting a new upstream release, repeat the actual workflow with authorized accounts and apps. Synthetic tests and builds of the current pinned version do not replace this testing.
- Before any public release, including previews, review repository metadata and confirm [SECURITY.md](../SECURITY.md) lists the owner-approved private reporting address, `support@v-ax.com`. GitHub private vulnerability reporting is not claimed to be enabled.
- Review the source package, original-code MIT choice, and any future binary-distribution license inventory.
- Approve the chosen date tag and publication explicitly. Do not tag a preview as universally compatible.

## What source checks cover

Public checks cover the selected source inventory, Python syntax, and release-date format. They do not execute the private test suite or verify Apple services, real Keychain access, sudo, or decryption. Tool builds and a configured-machine workflow have been tested; the complete first-run flow on a Mac without IPA Loom remains unverified. Commit-tree checks do not scan ancestor history; history, author metadata, and final release packages still need manual review.
