# Operations, recovery, and cleanup

Use `ipa-loom.command --help`. Runtime state lives outside the source checkout. `--doctor` is read-only: it checks the recorded tool hashes and model presence without creating storage or recovering setup; it is not a login or cryptographic model test.

## Setup rollback

Any setup failure stops further stages. When child termination and file ownership are confirmed, rollback removes the temporary installation and deletes any newly created Keychain item using that transaction's random scope. Otherwise staging is preserved for inspection. Existing configured installations are never overwritten. After an interruption, setup or `--recover` reads the saved setup journal to determine what completed. An activated installation is retained; unfinished staged changes are rolled back. Cleanup stops if a recorded child process may still be running. If Keychain deletion is denied, staged recovery data stays available for a later retry.

Interrupted model recovery still attempts scoped ownership restoration. If that fails, staging and its recovery marker remain for `--recover`; Loom does not use a broad privileged delete.

Power loss, full disks, and corrupted/unrecognized markers can require manual inspection; the tool refuses ambiguous deletion rather than treating an unknown folder as its own. Do not manually edit markers to bypass that protection. Do not delete a lock while a process may still be alive.

## Routine runs

Successful runs retain `output` and `private-logs`, and remove the temporary `input` and `tmp` directories. Failed runs also remove partial output when child termination is confirmed; uncertain runs retain their files. Existing input IPAs are copied, not deleted. Installed iOS `.app` targets are read through directory descriptors without following links, packaged only in the private run input directory, and rechecked after decryption; the `.app` path must not pass through a symbolic link or a non-folder. No source app is launched or written. An app update or unreadable source makes the run fail and discards its output. These checks detect source changes; they do not freeze TestFlight or prevent external updates. All runs and changing maintenance commands share the data-root lock. An unresolved child-process journal blocks new runs and deletion, even if its PID has disappeared. Noninteractive tools use a separate process group; terminal prompts retain the controlling terminal. After a hard kill or uncertain terminal interruption, inspect the remaining processes before manual recovery; do not clear journal fields to force cleanup. These controls assume trusted synchronous tools, not arbitrary background daemons. The wrapper does not retry an entire failed run or request purchases; ipatool may internally renew an expired token using saved credentials.

`--login` explicitly refreshes authentication. Setup generates an unknown random unlock key and stores it in a per-installation Keychain item (`io.ipaloom.file-keyring.v1`). If that key is missing, restore your own Keychain backup or use `--reset --apply` and set up again; entering your Apple password cannot unlock that state.

Installed-app records include `input_kind=installed-app`, `source_copy_verified`, and `installed_app_unchanged` when their checks complete, plus the ordinary decryption verification. A missing check is not a passed check. Bundle identities and output names in these records remain private.

## Cleanup commands

- `--clean-runs`: preview removal of all run outputs and diagnostics; summaries remain. Add `--apply` to delete.
- `--reset`: preview removal of tools, state, models, caches, run outputs, summaries, diagnostics, and the installation's Keychain item. Add `--apply` to delete. A small data-root marker, lock, and cleanup receipt remain so partial deletion can be retried safely. Resume an unfinished cleanup with the same command before starting setup or another cleanup action.
- `python3 -B scripts/clean_run.py RUN_ID`: preview one closed run (RUN_ID is the 32-character hex id before `.json` in a `Record:` path, or the `runs/<id>/` folder of an output path); add `--apply` to delete it and keep its summary.

A run left at `status: running` after an interrupted process is not cleaned individually; once you have confirmed no related process is still running, remove it with `--clean-runs --apply`. Keep any authorized output you want before applying removal. Cleanup does not remove the Mac App Store app, installed apps, Apple developer tools, system login, purchase history, or external backups. It is file removal, not secure erasure.

Never share raw diagnostic reports, account details, model/capture/license files, personal paths, identifying IPA measurements, or app packages. Removing account metadata does not authorize app redistribution.

## Retry a failed attempt

| Situation | Next action |
|---|---|
| Incorrect password or Apple asks to authenticate again | Retry the entry point; use `--login` on an already configured installation to refresh authentication locally |
| Setup stopped normally | Read the stage/error, correct its cause, and rerun `--setup`; the failed staging area is rolled back |
| Setup was interrupted | Run `--recover`; a recorded live PID requires waiting; an unresolved lifecycle marker requires process inspection and manual recovery, even after that PID disappears |
| Download or decryption failed | Correct the reported cause and rerun the target; partial output is never reported as a successful result |
| Tools/model readiness failed | Run `--doctor`; do not reset until you have inspected the cause and saved wanted outputs |

## Choose what to remove

```sh
./ipa-loom.command --clean-runs          # preview: outputs and diagnostics
./ipa-loom.command --clean-runs --apply  # remove those files; keep setup and summaries
./ipa-loom.command --reset              # preview: installation and private data
./ipa-loom.command --reset --apply      # remove them, including the scoped Keychain item
```

These are alternatives, not a sequence to run routinely. Neither command deletes the source checkout. Reset leaves a small ownership marker, lock, and receipt; it is not a promise to erase every trace on the Mac. See [security](../SECURITY.md) for data that must not be attached to reports.

## Input limits

IPA files are limited to 8 GiB, declared ZIP expansion to 32 GiB, and archive entries to 100,000. Plists are limited to 8 MiB and reports to 16 MiB; output hashes are streamed. These are rejection limits, not an OS resource sandbox. Compressed inputs can still take substantial time to validate. Output filename components are limited by UTF-8 bytes to fit filesystem limits.
