# Upstream roles and provenance

| Component | Pinned reference | Role | Local changes |
|---|---|---|---|
| [ipatool](https://github.com/majd/ipatool/tree/v2.8.0) | v2.8.0 | Apple authentication and personalized IPA download | File keyring only, explicit state/cache roots, no legacy state migration, passphrase validation, preparation progress, Apple ID prompt wording, private-FD secret input |
| [UnfairPlay](https://github.com/DrWhax/unfairplay/tree/v0.2.1) | v0.2.1 | Enrollment recovery, IPA decryption, plaintext report and account-data stripping | No source modifications used by this wrapper |
| Python wrapper | This repository | Ordering, manifest checks, output naming, verification and cleanup | Original integration code |
| Swift Keychain bridge | This repository | Non-synchronizing installation-scoped Keychain item | Original integration code |

The public ipatool delta is `patches/ipatool/0001-local-runtime.patch`, one consolidated patch against v2.8.0. Modified runtime behavior is documented here; upstream branding does not imply endorsement of these modifications.

Upstream responsibilities must stay explicit in project descriptions: this wrapper does not implement its own FairPlay decryption algorithm and does not turn an arbitrary Store link into a credential-free download.

The implemented route uses a Mac enrollment and does not require a jailbroken device. Installed TestFlight/iOS apps bypass ipatool: Loom packages a read-only copy of the installed iOS bundle and passes that IPA to the same UnfairPlay decryption and validation path. This does not add TestFlight invitation redemption or beta downloading to ipatool.

## License inventory

ipatool and UnfairPlay publish MIT licenses at the pinned references. UnfairPlay's NOTICE also credits Apache-2.0 DarkPhoenix code and MIT macOSFairFree code. The copies in `licenses/` preserve that provenance; see THIRD_PARTY_NOTICES.md. Binary redistribution would require an additional dependency/license inventory for the exact build, including the ipatool runtime dependencies. No upstream executable, Apple framework, model, or IPA is part of this source candidate.
