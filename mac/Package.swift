// swift-tools-version:6.0
// IPA Loom.app: a window on top of the IPA Loom engine (../scripts). The app starts the
// engine as a child process, reads the run records it writes, and shows the results. It
// holds no download, decryption or verification logic of its own.
import PackageDescription

let package = Package(
    name: "IPALoom",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "IPALoom", path: "Sources/IPALoom"),
    ],
    swiftLanguageModes: [.v5]
)
