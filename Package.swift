// swift-tools-version: 6.2
import Foundation
import PackageDescription

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let vendorInclude = "\(packageDir)/Vendor/Compression/include"
let vendorLib = "\(packageDir)/Vendor/Compression/lib"
let useVendorCompression = FileManager.default.fileExists(atPath: "\(vendorLib)/libzstd.a")

let compressionIncludeFlags: [String]
let compressionLinkFlags: [String]
if useVendorCompression {
    compressionIncludeFlags = ["-I\(vendorInclude)"]
    compressionLinkFlags = [
        "\(vendorLib)/libzstd.a",
        "\(vendorLib)/liblzma.a",
        "\(vendorLib)/liblz4.a"
    ]
} else {
    let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew/opt/zstd/lib/libzstd.a")
        ? "/opt/homebrew"
        : "/usr/local"
    compressionIncludeFlags = [
        "-I\(brewPrefix)/opt/zstd/include",
        "-I\(brewPrefix)/opt/xz/include",
        "-I\(brewPrefix)/opt/lz4/include"
    ]
    compressionLinkFlags = [
        "\(brewPrefix)/opt/zstd/lib/libzstd.a",
        "\(brewPrefix)/opt/xz/lib/liblzma.a",
        "\(brewPrefix)/opt/lz4/lib/liblz4.a"
    ]
}

let package = Package(
    name: "BoltZip",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v26)
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
                .unsafeFlags(compressionIncludeFlags)
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("archive"),
                .unsafeFlags(compressionLinkFlags)
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
