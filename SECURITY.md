# Security

## How IPA Loom is meant to run

IPA Loom runs on your own Apple Silicon Mac, under your macOS account, with apps and an Apple Account you are allowed to use. It builds and runs pinned tools locally and does not implement its own FairPlay decryption. ipatool is built from source; UnfairPlay is a downloaded, hash-pinned prebuilt executable, and model setup runs it once with administrator rights (`sudo`).

Apart from the Keychain item, everything it stores lives under the private data root `~/Library/Application Support/IPA Loom/`, or an explicit `IPA_LOOM_DATA_HOME`:

| Data | Handling |
|---|---|
| Apple password and token | ipatool's encrypted state |
| State-unlock key | A non-synchronizing local Keychain item, scoped to the installation and generated at setup |
| Enrollment model | Private data root; never in the source |
| Downloaded or decrypted IPA and raw diagnostics | Private run directories; can identify an app or account |
| Run summaries | Private records |
| Administrator password | Entered locally for `sudo`; not stored |

File encryption and permissions do not protect this data from software that already controls your macOS account, and there is no secure-erasure guarantee.

## Keep in mind

- IPA Loom removes the App Store FairPlay protection from an app and writes a decrypted IPA. It does not re-sign it, and a passed verification is not Apple signature trust, installability, or permission to redistribute the app.
- It signs in to Apple through ipatool, an unofficial client, using your Apple Account. Apple may require extra verification or limit an account used this way.
- It does not check that a local IPA or an installed app belongs to the signed-in account; ownership is left to Apple and the enrollment model. Use only apps you are authorized to inspect.
- A TestFlight build is beta software under the developer's and Apple's TestFlight terms and is often confidential. You install it through TestFlight yourself; IPA Loom reads a copy of the installed app and does not check your eligibility.
- Setup and downloads reach the network, including but not limited to Go and the pinned tool sources (`go.dev`, `api.github.com`, `github.com`, and the hosts they redirect to, such as `dl.google.com` and `codeload.github.com`), Go's module proxy and checksum database (`proxy.golang.org`, `sum.golang.org`, falling back to a module's own source when the proxy lacks it), and Apple during sign-in and download. On first login ipatool also fetches a framework from Apple into the local cache.
- A decrypted IPA still carries identifying metadata. Review a diagnostic or summary before sharing it, and never share credentials, the model, or raw reports.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Email [support@v-ax.com](mailto:support@v-ax.com) instead. You can also use GitHub's **Report a vulnerability** button on this repository.

Include IPA Loom's version or the commit you installed from, the macOS version and architecture, minimal steps to reproduce with fictional inputs where possible, and the expected and observed results. Redact sensitive information from errors and screenshots.

Do not send passwords, tokens, verification codes, private keys, Keychain contents, enrollment models, account data, personalized IPAs, capture or license files, or raw diagnostics. Include only what is needed to reproduce the problem.

For ordinary usage questions and non-sensitive bugs, use this repository's issue tracker.
