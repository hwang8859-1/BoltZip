import AppKit
import CryptoKit
import Foundation

// Compiled alongside `Sources/BoltZipCore/Icons/*.swift` by `Scripts/build_app.sh`:
// swiftc -O -parse-as-library Sources/BoltZipCore/Icons/*.swift Scripts/{generate_icon,IconResourceCompression}.swift \
//   -framework AppKit -framework CoreGraphics -o <bin>

@main
struct BoltIconGeneratorCLI {
    // Keep normal and Retina Finder sizes through 256 physical pixels. The App icon has its own full-size assets.
    static let documentIconMaxPixels = 256
    static let specs: [(String, Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]

    static func writeIconset(at iconsetURL: URL, maxPixels: Int = 1024, renderPNG: (Int) -> Data?) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: iconsetURL.path) {
            try fm.removeItem(at: iconsetURL)
        }
        try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
        for (filename, px) in specs where px <= maxPixels {
            guard let png = renderPNG(px) else {
                throw NSError(domain: "BoltIconGenerator", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to render \(filename)"
                ])
            }
            try png.write(to: iconsetURL.appendingPathComponent(filename))
        }
    }

    static func convertToIcns(iconsetURL: URL, outputIcnsURL: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        proc.arguments = ["-c", "icns", iconsetURL.path, "-o", outputIcnsURL.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "BoltIconGenerator", code: Int(proc.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "iconutil failed for \(iconsetURL.lastPathComponent)"
            ])
        }
    }

    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let first = args.first else {
            fputs("Usage:\n  generate_icon <output.iconset>\n  generate_icon --resources <Contents/Resources>\n", stderr)
            exit(1)
        }

        if first == "--version-document-icons", args.count == 3 {
            let resources = URL(fileURLWithPath: args[1], isDirectory: true)
            let plistURL = URL(fileURLWithPath: args[2])
            var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
            var names: [String: String] = [:]
            for kind in BoltDocumentIconKind.allCases {
                let original = resources.appendingPathComponent(kind.icnsBaseName + ".icns")
                let digest = SHA256.hash(data: try Data(contentsOf: original)).prefix(8).map { String(format: "%02x", $0) }.joined()
                let versioned = kind.icnsBaseName + "-" + digest
                try FileManager.default.moveItem(at: original, to: resources.appendingPathComponent(versioned + ".icns"))
                names[kind.icnsBaseName] = versioned
            }
            for (key, iconKey) in [("CFBundleDocumentTypes", "CFBundleTypeIconFile"),
                                   ("UTImportedTypeDeclarations", "UTTypeIconFile"),
                                   ("UTExportedTypeDeclarations", "UTTypeIconFile")] {
                guard var declarations = plist[key] as? [[String: Any]] else { continue }
                for index in declarations.indices {
                    if let old = declarations[index][iconKey] as? String, let replacement = names[old] {
                        declarations[index][iconKey] = replacement
                    }
                }
                plist[key] = declarations
            }
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            return
        }

        if first == "--resources" {
            guard args.count >= 2 else {
                fputs("Missing <Contents/Resources> directory argument.\n", stderr)
                exit(1)
            }
            let resourcesURL = URL(fileURLWithPath: args[1], isDirectory: true)
            let fm = FileManager.default
            try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

            let workDir = fm.temporaryDirectory.appendingPathComponent("boltzip-iconsets-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: workDir) }
            let iconCompression = IconResourceCompression(workDirectory: workDir)

            for (name, whiteBackground) in [("BoltZipDockLight", true), ("BoltZipDockDark", false)] {
                guard let png = BoltIconArtwork.renderAppIconPNG(pixelSize: 512, whiteBackground: whiteBackground) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let optimizedPNG = try iconCompression.optimizePNG(png)
                try optimizedPNG.write(to: resourcesURL.appendingPathComponent(name).appendingPathExtension("png"))
            }

            let appIconBundle = workDir.appendingPathComponent("AppIcon.icon", isDirectory: true)
            let assetsDir = appIconBundle.appendingPathComponent("Assets", isDirectory: true)
            try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

            guard let foregroundPNG = BoltIconArtwork.renderAppIconForegroundPNG(pixelSize: 1024, whiteBackground: true) else {
                fputs("Failed to render foreground icon assets.\n", stderr)
                exit(1)
            }
            try foregroundPNG.write(to: assetsDir.appendingPathComponent("emblem.png"))

            let iconJSON = """
            {
              "fill-specializations": [
                {
                  "value": {
                    "linear-gradient": [
                      "srgb:1.00000,1.00000,1.00000,1.00000",
                      "srgb:0.91373,0.94510,0.98824,1.00000"
                    ],
                    "orientation": {
                      "start": { "x": 0.15, "y": 0.0 },
                      "stop": { "x": 0.35, "y": 1.0 }
                    }
                  }
                },
                {
                  "appearance": "dark",
                  "value": {
                    "linear-gradient": [
                      "srgb:0.19216,0.33333,0.54118,1.00000",
                      "srgb:0.06275,0.12157,0.23922,1.00000"
                    ],
                    "orientation": {
                      "start": { "x": 0.15, "y": 0.0 },
                      "stop": { "x": 0.35, "y": 1.0 }
                    }
                  }
                }
              ],
              "groups": [
                {
                  "layers": [
                    {
                      "image-name": "emblem.png",
                      "name": "bolt-emblem",
                      "position": {
                        "scale": 1.0,
                        "translation-in-points": [0, 0]
                      }
                    }
                  ]
                }
              ],
              "supported-platforms": {
                "squares": "shared"
              }
            }
            """
            try Data(iconJSON.utf8).write(to: appIconBundle.appendingPathComponent("icon.json"))

            let actoolProc = Process()
            actoolProc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            actoolProc.arguments = [
                "actool",
                appIconBundle.path,
                "--compile", resourcesURL.path,
                "--platform", "macosx",
                "--minimum-deployment-target", "26.0",
                "--optimization", "space",
                "--app-icon", "AppIcon",
                "--output-partial-info-plist", workDir.appendingPathComponent("assetcatalog_info.plist").path,
                "--warnings",
                "--errors"
            ]
            try actoolProc.run()
            actoolProc.waitUntilExit()
            if actoolProc.terminationStatus != 0 {
                fputs("Warning: xcrun actool failed (status \(actoolProc.terminationStatus)), falling back to AppIcon.icns via iconutil.\n", stderr)
                let appIconset = workDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
                try writeIconset(at: appIconset) { px in
                    BoltIconArtwork.renderAppIconPNG(pixelSize: px, whiteBackground: false)
                }
                try convertToIcns(
                    iconsetURL: appIconset,
                    outputIcnsURL: resourcesURL.appendingPathComponent("AppIcon.icns")
                )
            }

            for kind in BoltDocumentIconKind.allCases {
                let docIconset = workDir.appendingPathComponent("\(kind.icnsBaseName).iconset", isDirectory: true)
                try writeIconset(at: docIconset, maxPixels: documentIconMaxPixels) { px in
                    BoltIconArtwork.renderDocumentIconPNG(kind: kind, pixelSize: px)
                }
                let output = resourcesURL.appendingPathComponent("\(kind.icnsBaseName).icns")
                try convertToIcns(iconsetURL: docIconset, outputIcnsURL: output)
                try iconCompression.compactICNS(at: output)
            }
        } else {
            let iconsetURL = URL(fileURLWithPath: first, isDirectory: true)
            try writeIconset(at: iconsetURL) { px in
                BoltIconArtwork.renderAppIconPNG(pixelSize: px, whiteBackground: false)
            }
        }
    }
}
