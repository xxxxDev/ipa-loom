# Preparing a source release

Tags use `vYYYY.M.D` without zero-padding, for example `v2026.11.9`. Choose the actual release date; the example is not an existing release. Dependency versions are separate. Do not move an already published tag to another commit.

## Review before publication

- Review the working directory and tracked/untracked file list. `PUBLIC-FILES.txt` lists every intentional public file. The test suite is maintained privately outside the source repository; do not package it, the private data root, or private acceptance evidence.
- Read the paired README documents for equivalent claims; equal line counts alone do not prove translation quality. Only README.zh-TW.md is in Traditional Chinese; all other public text and documentation images use English, except the native language name in the English README's language-switch link. Check relative links.
- Review documentation images visually and inspect their metadata. Only the exact PNG paths and SHA-256 values in `scripts/check_public.py` bypass text decoding; a new inventory entry alone does not permit another image. Review replacement pixels before updating a hash. Keep actual captured output distinct from synthetic illustrations, and never use an illustration as evidence that account/model setup passed.
- Review third-party licenses, pinned hashes, and the consolidated patch. The source license inventory does not authorize redistribution of bundled executables, Apple frameworks, models, or apps.
- Follow [release readiness](RELEASE-READINESS.md). Source inventory, syntax, and date checks do not validate runtime behavior. A build-only or already-configured-machine run does not validate new-user setup.
- Verify that [SECURITY.md](../SECURITY.md) lists the owner-confirmed private reporting address, `support@v-ax.com`. This does not imply GitHub private vulnerability reporting is enabled.
- Manually review the history and author metadata that a push would expose, not just the final files. Automated tree checks do not scan ancestor history or approve author identities.

## Check the exact version you plan to release

The source checker validates inventory and Python syntax without executing the source. It defaults to the working directory. `--staged` checks the Git index; `--ref COMMIT` checks that commit's immutable tree and prints its full commit OID. These are distinct targets, not interchangeable evidence.

1. Check the working directory, source syntax, and proposed date. These commands do not create a repository, tag, or release:

   ```sh
   python3 -B scripts/check_public.py
   python3 -B scripts/check_release.py v2026.11.9
   ```

2. Stage only reviewed public files. Review the staged diff first, then check the index:

   ```sh
   git diff --cached
   python3 -B scripts/check_public.py --staged
   ```

3. Commit the reviewed index, then check the resulting commit tree:

   ```sh
   python3 -B scripts/check_public.py --ref HEAD
   ```

   Record the full OID printed by the checker with the review result. A successful check covers that tree only, not its ancestors. If the candidate changes, repeat the affected review and checks and record the new OID. The committed-tree check includes Python syntax for that tree, without executing it.

4. Before an owner-approved push, confirm the outgoing ref points to that exact reviewed OID and manually review its reachable history and author metadata. Push only the reviewed version, not a newer unreviewed `HEAD` or unrelated refs. Do not create a remote repository or tag in advance of approval.

## Write the release notes and inspect the package

Move relevant entries from Unreleased into the chosen date section only when preparing that release. Use English sections New, Changes, Faster, and Fixes when applicable. Each bullet starts with a short bold title and explains the user-visible change. State supported environment, preview limitations, and the scope of verification; do not paste raw test output or private app details.

Prepare source archives from the reviewed commit. Manually inspect the final archive listing and contents before upload against the reviewed public inventory. A successful tree check does not validate a separately assembled archive. No private test suite, runtime, real IPA, credential, diagnostic archive, or personal screenshot belongs in a release.

## Automation boundaries

`.github/workflows/source.yml` provides source-inventory and syntax checks on pushes and pull requests, and date-format validation on tag pushes. It does not run the private test suite, create tags, or publish assets. Remote CI runs after content reaches the remote: it cannot prevent first exposure of an unsafe push. Passing CI establishes neither account/model behavior nor absence of all private information.

The separate upstream workflow detects and builds candidates as described in [UPDATES.md](UPDATES.md). Passing those checks does not automatically approve a release. Publication remains an owner-approved maintainer action; no remote repository, workflow run, or published release is implied by local checks.
