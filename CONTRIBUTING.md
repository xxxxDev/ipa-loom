# Contributing

Thanks for helping. IPA Loom is a small project, so a short, focused change is the easiest to review.

## Before you start

- For a bug, open an issue with what you did, what you expected and what happened, plus the version or commit you installed from and your macOS version and architecture.
- For a larger change or a new feature, open an issue first so we can agree on the approach.
- For a security problem, follow [SECURITY.md](SECURITY.md) instead.

## Development

IPA Loom runs on an Apple Silicon Mac. Double-click `ipa-loom.command`, or run `./ipa-loom.command` in its folder; first use builds the pinned tools and guides setup. The scripts are Python 3 and need no build step.

The project's test suite is maintained separately and is not part of this repository. In your pull request, describe how you checked the change: what you ran, on which macOS version, and what you saw. Do not claim a fresh-machine result from an already-configured machine.

## Guidelines

- Match the style of the code around your change.
- Keep setup, decryption, verification, and cleanup behavior explicit; do not weaken a safety check or a failure path to make something pass.
- Text shown to people comes in English and Traditional Chinese: change `README.md` and `README.zh-TW.md` together and keep them the same number of lines. Other documents and command output are in English.
- Code comments are in English and say why, not what.
