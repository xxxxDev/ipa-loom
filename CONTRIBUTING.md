# Contributing

Keep changes small and focused. Discuss major workflow or credential-handling changes in an issue before implementing them. Never include credentials, models, apps, framework caches, raw logs, or local test evidence in an issue or pull request.

The test suite and its evidence are maintained privately outside this source repository and are not published. In your pull request, describe the platform and tool versions, how you checked the behavior and failure paths, the results, and anything not verified. Do not claim a fresh-machine test from a configured-machine run. Keep README.md and README.zh-TW.md semantically paired with matching line counts. Only the README has a Traditional Chinese edition; code, comments, command-line messages, images, and all other public project documents use English.

Use English, single-line commit titles in the form `Area: describe the behavior and reason: files`. Preserve external contributors' own authorship. Do not add generated-by or co-author trailers automatically. Releases use date tags such as `v2026.11.9` (`vYYYY.M.D`, no zero-padding), with English sections New, Changes, Faster, and Fixes only when applicable. Each release bullet has a bold short title and explains the user-visible change without internal filenames or test details.

Run `python3 -B scripts/check_public.py` to check the working directory against `PUBLIC-FILES.txt`. Add each intentional public file to that inventory; keep the private test suite and its fixtures outside the source repository. Public checks cover source inventory, syntax, and release-date format, not runtime behavior. Before a release, review `git diff --cached`, check the index with `python3 -B scripts/check_public.py --staged`, then check the committed tree with `python3 -B scripts/check_public.py --ref HEAD` and record its full commit OID. Follow [the release checklist](docs/RELEASING.md), including manual history and package review. Pushes, tags, and releases require the repository owner's approval. Do not force-push.

Validate a proposed tag with `python3 scripts/check_release.py v2026.11.9`. This check does not create a tag or publish anything.
