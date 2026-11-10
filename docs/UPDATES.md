# Checking and testing upstream updates

IPA Loom checks new upstream versions separately from the installed tools. A successful check does not install an update. IPA Loom's release dates and dependency versions are separate. `config/dependencies.json` pins verified installation inputs. Neither the detector nor the candidate test modifies this file or the active runtime.

## 1. Find new releases

Run `python3 -B scripts/check_updates.py`. The detector reads each official GitHub repository's latest stable release, excludes draft/prerelease responses, compares numeric versions, and reports the pinned/latest versions. It does not infer compatibility from release recency or commit count. API/network errors fail the check instead of reporting “current”.

Use `--report /new/path/report.json` to save a report containing selected update information; existing reports are not overwritten. It contains versions, source URLs, new-version hashes, and check results, not private runtime data or raw logs.

## 2. Build and check the new version

Add `--verify`. Only when a newer release exists, the checker prepares a temporary dependency manifest for testing. ipatool's tag is resolved to a commit and its HTTPS source snapshot is hashed; this observed hash is not a signed release attestation. UnfairPlay requires a release asset digest or a matching publisher SHA256SUMS entry. If checksums are missing or ambiguous, testing stops.

The new version is built in a separate temporary data directory. Build processes receive only the environment settings they need. It checks extraction safety, the consolidated patch, Go/Swift builds, tool startup, and required auth/download/setup/decrypt CLI flags. The pinned Go version is not silently upgraded: an incompatible new toolchain requirement fails for review. Temporary build data is removed. This is filesystem isolation, not an OS security sandbox for hostile upstream code.

## 3. Test the actual workflow locally

A successful build returns `needs-private-regression`: the tools passed build and command-interface checks, but still need testing with an authorized account and app. This status does not mean the version is approved or installed.

The maintainer performs these regression tests locally to confirm that existing behavior still works: fresh login/2FA, model setup, matching-IPA decryption, plaintext report schema/coverage, account stripping, failure rollback, and cleanup. These tests use private credentials, enrollment models, and real app packages, so they stay outside public CI. Ordinary users are not expected to run the maintainer acceptance suite. Public CI cannot establish that these account-dependent operations work.

## 4. Schedule checks and adopt a tested version

`.github/workflows/upstream.yml` runs daily and on manual dispatch on a GitHub-hosted Apple Silicon Mac, with read-only repository permissions and no persisted checkout credentials. It uploads only the update report described above. It becomes active only after the repository/workflow is published and Actions is enabled; no remote schedule is claimed to be running yet.

If any check fails, retain the currently pinned versions and installed tools. After reviewing source/license changes, checksums, patch changes, and the local regression results, a maintainer can approve a change to the pinned dependency versions and an IPA Loom release. Tags use `vYYYY.M.D`, for example `v2026.11.9`, without zero-padding. No script pushes, creates a release, or upgrades existing tools automatically. Existing verified installations stay usable while candidates are tested; reset/reinitialize only when intentionally adopting a reviewed new release, retaining any needed authorized results first.

## What each type of test establishes

The separate `source.yml` workflow checks source inventory and Python syntax on pushes and pull requests, and release-date format on tag pushes. The test suite is maintained privately outside the source repository and is not run by public CI. Upstream builds check tool compatibility without private credentials. Only an authorized private run can exercise Apple login, enrollment recovery, and real plaintext verification. Release notes should distinguish these three results:

| Test | What it establishes | What it does not establish |
|---|---|---|
| Public source checks | Source inventory, Python syntax, and release-date format | Runtime behavior, Apple login, or decryption |
| New-version build checks | Build success, tool startup, and required command interfaces | Successful account/model operations |
| Maintainer tests with authorized accounts and apps | Results observed on the tested machine, app, and versions | Compatibility with every app or Mac |

If a candidate builder is interrupted or leaves an unresolved child-process journal, its temporary workspace is retained and its path is shown for inspection. Completed, quiescent builds are removed. Do not remove a retained workspace while a build process may still be writing to it. Candidate verification executes upstream code with the runner account’s authority; use a disposable machine without personal credentials.
