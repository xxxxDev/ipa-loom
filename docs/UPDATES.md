# Checking and testing upstream updates

IPA Loom checks new upstream versions separately from the installed tools. A successful check does not install an update. IPA Loom's release dates and dependency versions are separate. `config/dependencies.json` pins verified installation inputs. Neither the detector nor the candidate test modifies this file or the active runtime.

## 1. Find new releases

Run `python3 -B scripts/check_updates.py`. The detector reads each official GitHub repository's latest stable release, excludes draft/prerelease responses, compares numeric versions, and reports the pinned/latest versions. It does not infer compatibility from release recency or commit count. API/network errors fail the check instead of reporting "current".

Use `--report /new/path/report.json` to save a report containing selected update information; existing reports are not overwritten. It contains versions, source URLs, new-version hashes, and check results, not private runtime data or raw logs.

## 2. Build and check the new version

Add `--verify`. Only when a newer release exists, the checker prepares a temporary dependency manifest for testing. ipatool's tag is resolved to a commit and its HTTPS source snapshot is hashed; this observed hash is not a signed release attestation. UnfairPlay requires a release asset digest or a matching publisher SHA256SUMS entry. If checksums are missing or ambiguous, testing stops.

The new version is built in a separate temporary data directory. Build processes receive only the environment settings they need. It checks extraction safety, the consolidated patch, Go/Swift builds, tool startup, and required auth/download/setup/decrypt CLI flags. The pinned Go version is not silently upgraded: an incompatible new toolchain requirement fails for review. Temporary build data is removed. This is filesystem isolation, not an OS security sandbox for hostile upstream code.

## 3. Confirm with a full run

A successful build returns `needs-full-run`: the tools passed build and command-interface checks, but a passing build is not a working version. Before a new version is adopted, a full authorized run with an account and app has to confirm that login, model setup, matching-IPA decryption, verification, and cleanup still work. This status does not mean the version is approved or installed.

## 4. Adopt a tested version

If any check fails, keep the pinned versions and installed tools. A new version is adopted only after a full authorized run confirms existing behavior still works; no script pushes, releases, or upgrades existing tools automatically. Existing installations stay usable while a candidate is tested.

## What each type of test establishes

Upstream builds check tool compatibility without private credentials. Only a full authorized run can exercise Apple login, enrollment recovery, and real plaintext verification. Release notes should distinguish these results:

| Test | What it establishes | What it does not establish |
|---|---|---|
| New-version build checks | Build success, tool startup, and required command interfaces | Successful account/model operations |
| A full authorized run with your account and apps | Results observed on the tested machine, app, and versions | Compatibility with every app or Mac |

If a candidate builder is interrupted or leaves an unresolved child-process journal, its temporary workspace is retained and its path is shown for inspection. Completed, quiescent builds are removed. Do not remove a retained workspace while a build process may still be writing to it. Candidate verification executes upstream code with the runner account's authority; use a disposable machine without personal credentials.
