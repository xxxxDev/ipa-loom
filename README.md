<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/logo/ipa-loom-lockup-on-dark.svg">
    <img src="docs/assets/logo/ipa-loom-lockup-primary.svg" alt="IPA Loom" width="640">
  </picture>
</p>

<h1 align="center">IPA Loom</h1>

<p align="center">
  <b>Download, decrypt, and verify IPAs on Apple Silicon Macs.</b><br>
  A local command-line workflow that uses your own Apple Account and no jailbroken device.
</p>

<p align="center">
  English · <a href="README.zh-TW.md">繁體中文</a>
</p>

## What it is

IPA Loom brings IPA download, decryption, verification, and cleanup together on an Apple Silicon Mac. Give it an App Store link, numeric App ID, local IPA, or installed iOS `.app`; one entry point guides setup and later runs.

It connects [ipatool](https://github.com/majd/ipatool) for Apple authentication and personalized downloads with [UnfairPlay](https://github.com/DrWhax/unfairplay) to recover the local enrollment model needed for decryption. Loom adds local credential storage, output naming, verification, recovery, and cleanup. It does not implement its own FairPlay decryption algorithm, and it does not turn a bare Store link into a credential-free download.

## Features

- One launcher for first setup and for later Store-link, App ID, local-IPA, and installed iOS-app runs.
- Local sign-in with your Apple Account; the state-unlock key stays in your Keychain.
- Decryption through a recovered on-device enrollment model, with no jailbroken device.
- First setup also leaves the app you chose decrypted as your first result; the same model is then used for the later apps you decrypt.
- Verification that a run produced a complete plaintext report, a matching hash, valid ZIP contents, unchanged app identity, and no `SC_Info` files.
- Recovery for an interrupted setup, and cleanup that previews before it removes.

## What it looks like

<p align="center">
  <img src="docs/assets/screens/ipa-loom-setup-flow-en.png" alt="First-run setup flow in five steps: prepare tools, choose your installed app, sign in to Apple, download its encrypted App Store copy and build a reusable decryption model, then verify; afterwards decrypt other apps" width="900">
</p>

How first-run setup builds the reusable decryption model: your installed app already runs on this Mac, its App Store copy is still encrypted, and UnfairPlay uses the pair to recover the model.

<p align="center">
  <img src="docs/assets/screens/ipa-loom-help.png" alt="IPA Loom help output: setup, readiness checks, recovery, build checks, cleanup, login and output naming" width="900">
</p>

The actual English `--help` output, typeset for readability. Run `./ipa-loom.command --help` for the current full list. Capturing it did not run setup or reach an Apple account.

<p align="center">
  <img src="docs/assets/screens/ipa-loom-workflow.png" alt="Synthetic workflow illustration: session check, download, decryption, plaintext verification and a fictional Example App IPA; not a real decryption result" width="900">
</p>

**Synthetic illustration, not a live run.** It shows the session check, download, decryption, verification and example output; no account, private model, or real IPA was used.

## Requirements

- An Apple Silicon Mac, with Apple Command Line Tools (offered through Apple's installer if missing) and Python 3.9 or later.
- Network access for setup and downloads.
- An Apple Account entitled to the app.
- For first model setup: an installed, opened iPhone or iPad app from the Mac App Store and its matching IPA.

## Quick start

Download and unzip the source, open its folder, and double-click `ipa-loom.command`. Or open a terminal there:

```sh
./ipa-loom.command
```

First use builds pinned tools and guides Apple login, matching-app checks, model recovery, and verification. ipatool is built from source; UnfairPlay is a hash-pinned prebuilt binary, run once with administrator rights (`sudo`) during model setup. Apple password, 2FA, Keychain authorization, and the macOS administrator prompt are handled locally. The generated unlock key is saved in your Keychain after setup. Setup ends by keeping the app you chose decrypted as your first result and printing its path. See [first-run setup](docs/SETUP.md).

## Use it

Run the same command and give a target, as an argument or at the prompt. An App Store app can be decrypted three ways: its App Store link, its numeric App ID, or, when it is installed on this Mac, its `.app` path. The `.app` path route accepts an installed iPhone or iPad app from either source, TestFlight betas included; an existing `.ipa` works too:

```sh
./ipa-loom.command "/path/to/Example.ipa" --suffix my-tag
```

Store targets check the session and download before decryption. Local IPA and installed-app targets skip those two steps. Later runs reuse the configured model and Keychain item; renewed Apple authentication or Keychain access may still need your input. A relative path is read from the launcher's own folder, so give a local IPA an absolute path.

Output uses `StoreName_Version_loom.ipa`. The Store name comes from IPA metadata, with app-name fallbacks. `--suffix` changes only the filename label, not code signing. The terminal prints the output location.

### Installed apps (App Store or TestFlight)

After setup, give the `.app` path of an installed iPhone or iPad app. A TestFlight beta cannot be downloaded, so install it through TestFlight on this Mac first and decrypt it from its installed `.app`, then run:

```sh
./ipa-loom.command "/Applications/Example.app" --suffix my-tag
```

You can also enter the `.app` path at the prompt. Loom reads the iOS bundle inside its Mac wrapper, copies it into a private IPA, decrypts and verifies that copy, and checks that the source bundle is unchanged. It does not launch, re-sign, or write to the installed app. If TestFlight updates the bundle during the run, Loom rejects the result; retry after the update finishes.

This route needs an existing verified model; it does not initialize one from a TestFlight app. A `https://testflight.apple.com/join/...` or `itms-beta://...` link opens an invitation, not an IPA download: install the beta through TestFlight first. Native Mac apps and iOS bundles with internal symlinks or special files are not supported. See [Limits](#limits) for the account and beta-software risks.

## What success means

A passed run requires a complete plaintext-verification report, a matching output hash, valid ZIP contents, unchanged app identity and version, and no `SC_Info` files. A successful download or a zero exit code alone is not enough.

## Your data

Tools, encrypted account state, the private model, caches, outputs, and records live outside the source folder under `~/Library/Application Support/IPA Loom/`. The Keychain holds a separate non-synchronizing unlock key. ipatool's encrypted state includes your Apple password and token, so this directory must stay private. No account, model, or real IPA ships with the source. Read [security](SECURITY.md) before sharing diagnostics.

## Recover or clean up

Setup prepares files in a temporary directory and activates the installation only after verification. Ordinary failures roll back; uncertain child termination or failed ownership restoration keeps staging for inspection. Use `./ipa-loom.command --recover` after an interrupted setup, or `--doctor` to check readiness.

`--clean-runs` previews removal of run outputs and diagnostics while keeping setup and summaries. `--reset` previews removal of the private runtime and its Keychain item. Add `--apply` to perform it. Save wanted outputs first. Apple developer tools, installed apps, the Mac App Store sign-in, and external backups are not removed. See [operations](docs/OPERATIONS.md).

## Limits

- **Preview.** Tool builds and the local workflow on an already-configured Mac have passed testing. The complete first-run flow, from Apple login and model setup through decryption, still needs independent testing on a Mac without IPA Loom installed. Not every app or macOS version is guaranteed to work.
- **It removes FairPlay protection.** IPA Loom writes a decrypted IPA of the app. The output is **not re-signed**; a passed verification is not Apple signature trust, installability, correct behavior, or permission to redistribute.
- **It uses your Apple Account** through ipatool, an unofficial client. Apple may require extra verification or limit an account used this way.
- **It does not check ownership.** A local IPA or installed app is accepted without checking that it belongs to the signed-in account; that is left to Apple and the model. Use only apps you are authorized to inspect.
- **TestFlight builds** are beta software under the developer's and Apple's TestFlight terms, often confidential, and eligibility is not checked.
- **It reaches the network** during setup and downloads, including but not limited to `go.dev`, `api.github.com`, `github.com`, the hosts they redirect to, Go's module proxy and checksum database, and Apple (sign-in, download, and a framework fetch). See [security](SECURITY.md).

## Documentation

- [Features](docs/FEATURES.md) · [Setup and prompts](docs/SETUP.md)
- [Recovery and cleanup](docs/OPERATIONS.md) · [Update testing](docs/UPDATES.md)
- [Upstream components and licenses](docs/UPSTREAM.md)

## Security

IPA Loom handles your Apple credentials, an enrollment model, and decrypted app packages locally. See [SECURITY.md](SECURITY.md) for how it is meant to run, the risks, and how to report a vulnerability.

## Contributing

Issues and small, focused pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

The code is under the [MIT License](LICENSE). The logo isn't: see [BRAND.md](BRAND.md).

Third-party components keep their own licenses: see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

IPA Loom is an independent project. It is not made by, affiliated with or endorsed by Apple. Apple is a trademark of Apple Inc.

Made by [V-AX](https://v-ax.com).
