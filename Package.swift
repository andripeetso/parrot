// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "parrot",
    platforms: [.macOS(.v14)],
    products: [
        // The dictation engine, for apps that link it without Parrot's app parts.
        .library(name: "ParrotCore", targets: ["ParrotCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // WhisperKit, renamed argmax-oss-swift. 1.1.0 is the first release with
        // argmax-oss-swift#514: before it, any transcription with promptTokens
        // came back empty, which the dictionary's example sentence relies on.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.0"),
        // In-app updates (#50). A binary framework: scripts/build-app.sh
        // embeds it in Parrot.app/Contents/Frameworks and signs it.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
    ],
    targets: [
        // The engine: capture, the hotkey gesture, transcription, the
        // dictionary. No UI, no settings store, no updater.
        .target(
            name: "ParrotCore",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        // The app: dictation loop, delivery at the cursor, settings, UI, updater.
        .target(
            name: "ParrotApp",
            dependencies: [
                "ParrotCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        // Thin entry point: ArgumentParser commands that call into ParrotApp.
        .executableTarget(
            name: "parrot",
            dependencies: [
                "ParrotApp",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // Developer benchmarks (#49, #52), not shipped in Parrot.app:
        // swift run -c release parrot-bench transcription|capture ...
        .executableTarget(
            name: "parrot-bench",
            dependencies: [
                "ParrotCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // Unit tests against ParrotCore and ParrotApp.
        .testTarget(
            name: "ParrotTests",
            dependencies: ["ParrotCore", "ParrotApp"]
        ),
        // Unit tests for the benchmarks' pure parts.
        .testTarget(
            name: "ParrotBenchTests",
            dependencies: ["parrot-bench"]
        ),
    ]
)
