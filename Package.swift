// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoltZip",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS("27.2")
    ],
    products: [
        .library(name: "BoltZipCore", targets: ["BoltZipCore"]),
        .executable(name: "boltzip", targets: ["BoltZipCLI"]),
        .executable(name: "BoltZipApp", targets: ["BoltZipApp"])
    ],
    targets: [
        .target(
            name: "CBoltCompression",
            path: "Sources/CBoltCompression",
            cSettings: [
                .unsafeFlags([
                    "-I/opt/homebrew/opt/zstd/include",
                    "-I/opt/homebrew/opt/xz/include",
                    "-I/opt/homebrew/opt/lz4/include"
                ])
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .unsafeFlags([
                    "/opt/homebrew/opt/zstd/lib/libzstd.a",
                    "/opt/homebrew/opt/xz/lib/liblzma.a",
                    "/opt/homebrew/opt/lz4/lib/liblz4.a"
                ])
            ]
        ),
        .target(
            name: "BoltZipCore",
            dependencies: ["CBoltCompression"],
            path: "Sources/BoltZipCore"
        ),
        .executableTarget(
            name: "BoltZipCLI",
            dependencies: ["BoltZipCore"],
            path: "Sources/BoltZipCLI"
        ),
        .executableTarget(
            name: "BoltZipApp",
            dependencies: ["BoltZipCore"],
            path: "Sources/BoltZipApp"
        ),
        .testTarget(
            name: "BoltZipCoreTests",
            dependencies: ["BoltZipCore"],
            path: "Tests/BoltZipCoreTests"
        )
    ]
)
