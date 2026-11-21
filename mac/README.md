# IPA Loom for Mac

A native window over the same engine the terminal command runs. It starts the engine, reads the records the engine writes, and shows your decrypted apps. It holds no account, model or IPA of its own: everything stays in the private data folder (`~/Library/Application Support/IPA Loom`), shared with `ipa-loom.command`.

The app is dark only and uses Liquid Glass on macOS 26 and later, with a plain material on macOS 14 and 15.

## Build

From the repository root, double-click `ipa-loom-app.command`, or run:

```sh
mac/build-app.sh
open "mac/build/IPA Loom.app"
```

Apple's Command Line Tools are enough; Xcode is not needed. The build copies the engine (`scripts`, `config`, `patches`, `native`, `licenses`) into the app, so the app keeps working if this folder moves. The signature is ad hoc: made on this Mac, for this Mac.

## What it does today

| Page | What it shows |
| --- | --- |
| Decrypt | Paste an App Store link or App ID, or drop an `.ipa` or an installed `.app`. Shows the run's steps and files, and can cancel it. |
| Library | Every decrypted app still on disk, with its files and a Show in Finder link. |
| Activity | Every run the engine has recorded. |
| Setup & Health | Whether the engine is ready, and where your private data is. |

Not in the app yet:

- First-time setup and Apple sign-in still happen in Terminal. The app opens it for you from Setup & Health.
- The encrypted original is not kept after a run, so the Library shows it as not kept.

## Layout

```
mac/
  Package.swift           Swift package, one executable target
  build-app.sh            builds and signs "IPA Loom.app" into mac/build/
  AppIcon.svg             icon source; Resources/AppIcon.icns is made from it
  Sources/IPALoom/
    IPALoomApp.swift      entry point, window and menus
    AppModel.swift        app state and the running session
    Engine.swift          starts the engine and reads its records
    Look.swift            colours, glass, backdrop and shared pieces
    RootView.swift        sidebar and page frame
    DecryptPage.swift     link field, drop area and the run view
    LibraryPage.swift     Library and Activity
    HealthPage.swift      Setup & Health
    Snapshot.swift        debug only: draws each page to a PNG file
```

## Check the layout without opening a window

A debug build can draw every page to PNG files with sample data. It does not start the engine or read your private data.

```sh
cd mac && swift build
IPA_LOOM_APP_SNAPSHOT=/tmp/ipa-loom-pages .build/debug/IPALoom
```

The pictures show the layout, not the glass, which the window server adds.
