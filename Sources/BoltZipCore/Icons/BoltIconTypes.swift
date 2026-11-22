#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

public enum BoltDocumentIconMotif: Sendable {
    case archiveBrackets
    case tarLayers
    case streamChevrons
    case diskRings
}

/// Four semantic archive families from BoltZip Icon System v2.
public enum BoltIconFamily: String, CaseIterable, Sendable {
    case archive
    case tarball
    case stream
    case image

    public var motif: BoltDocumentIconMotif {
        switch self {
        case .archive: return .archiveBrackets
        case .tarball: return .tarLayers
        case .stream: return .streamChevrons
        case .image: return .diskRings
        }
    }

    /// Unified family gradient colors `(c1, c2, deep)` in sRGB.
    public var ramp: (c1: (CGFloat, CGFloat, CGFloat), c2: (CGFloat, CGFloat, CGFloat), deep: (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .archive:
            return (
                c1: (0.227, 0.753, 1.000), // #3AC0FF
                c2: (0.165, 0.388, 0.941), // #2A63F0
                deep: (0.106, 0.247, 0.659) // #1B3FA8
            )
        case .tarball:
            return (
                c1: (1.000, 0.761, 0.290), // #FFC24A
                c2: (0.937, 0.478, 0.086), // #EF7A16
                deep: (0.659, 0.314, 0.039) // #A8500A
            )
        case .stream:
            return (
                c1: (0.655, 0.545, 0.980), // #A78BFA
                c2: (0.416, 0.294, 0.941), // #6A4BF0
                deep: (0.278, 0.184, 0.659) // #472FA8
            )
        case .image:
            return (
                c1: (0.624, 0.690, 0.776), // #9FB0C6
                c2: (0.298, 0.361, 0.455), // #4C5C74
                deep: (0.173, 0.227, 0.306) // #2C3A4E
            )
        }
    }
}

/// Optical rendering tiers so icons remain crisp from 16px Finder lists up to 1024px Quick Look.
public enum BoltIconScale: Sendable {
    case full
    case medium
    case small
    case micro

    public init(pixelSize: Int) {
        switch pixelSize {
        case ..<24:  self = .micro
        case ..<56:  self = .small
        case ..<120: self = .medium
        default:     self = .full
        }
    }
}

public enum BoltDocumentIconKind: String, CaseIterable, Sendable {
    case zip
    case rar
    case sevenZip
    case tar
    case tgz
    case tzst
    case txz
    case tbz2
    case tlz4
    case gz
    case zst
    case xz
    case bz2
    case lz4
    case cab
    case xar
    case iso

    public var icnsBaseName: String {
        switch self {
        case .zip: return "DocZip"
        case .rar: return "DocRar"
        case .sevenZip: return "Doc7z"
        case .tar: return "DocTar"
        case .tgz: return "DocTgz"
        case .tzst: return "DocTzst"
        case .txz: return "DocTxz"
        case .tbz2: return "DocTbz2"
        case .tlz4: return "DocTlz4"
        case .gz: return "DocGz"
        case .zst: return "DocZst"
        case .xz: return "DocXz"
        case .bz2: return "DocBz2"
        case .lz4: return "DocLz4"
        case .cab: return "DocCab"
        case .xar: return "DocXar"
        case .iso: return "DocIso"
        }
    }

    public var badgeLabel: String {
        switch self {
        case .zip: return "ZIP"
        case .rar: return "RAR"
        case .sevenZip: return "7Z"
        case .tar: return "TAR"
        case .tgz: return "TGZ"
        case .tzst: return "TZST"
        case .txz: return "TXZ"
        case .tbz2: return "TBZ2"
        case .tlz4: return "TLZ4"
        case .gz: return "GZ"
        case .zst: return "ZST"
        case .xz: return "XZ"
        case .bz2: return "BZ2"
        case .lz4: return "LZ4"
        case .cab: return "CAB"
        case .xar: return "XAR"
        case .iso: return "ISO"
        }
    }

    public var family: BoltIconFamily {
        switch self {
        case .zip, .rar, .sevenZip:
            return .archive
        case .tar, .tgz, .tzst, .txz, .tbz2, .tlz4:
            return .tarball
        case .gz, .zst, .xz, .bz2, .lz4:
            return .stream
        case .cab, .xar, .iso:
            return .image
        }
    }

    public var motif: BoltDocumentIconMotif {
        family.motif
    }

    public var gradientColors: (top: (CGFloat, CGFloat, CGFloat), bottom: (CGFloat, CGFloat, CGFloat)) {
        let r = family.ramp
        return (r.c1, r.c2)
    }

    /// Resolves the matching BoltZip document icon kind from an archive filename (including compound `.tar.*`).
    public static func resolve(forFilename filename: String) -> BoltDocumentIconKind? {
        let lower = URL(fileURLWithPath: filename).lastPathComponent.lowercased()
        let compoundSuffixes: [(String, BoltDocumentIconKind)] = [
            (".tar.gz", .tgz),
            (".tar.zst", .tzst),
            (".tar.xz", .txz),
            (".tar.bz2", .tbz2),
            (".tar.lz4", .tlz4)
        ]
        for (suffix, kind) in compoundSuffixes where lower.hasSuffix(suffix) {
            return kind
        }

        let ext = (lower as NSString).pathExtension
        switch ext {
        case "zip", "zipx", "cbz": return .zip
        case "rar", "cbr", "r00": return .rar
        case "7z", "cb7": return .sevenZip
        case "tar": return .tar
        case "tgz": return .tgz
        case "tzst": return .tzst
        case "txz": return .txz
        case "tbz", "tbz2": return .tbz2
        case "tlz4": return .tlz4
        case "gz", "gzip": return .gz
        case "zst", "zstd": return .zst
        case "xz", "lzma": return .xz
        case "bz2", "bzip2": return .bz2
        case "lz4": return .lz4
        case "cab": return .cab
        case "xar", "pkg": return .xar
        case "iso": return .iso
        default:
            if ext.count >= 3, ext.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), (Int(ext) ?? 0) >= 1 {
                let baseExt = ((lower as NSString).deletingPathExtension as NSString).pathExtension
                if baseExt == "7z" || baseExt == "cb7" {
                    return .sevenZip
                }
            }
            if ext.hasPrefix("z"), ext.count == 3, ext.dropFirst().allSatisfy(\.isNumber) {
                return .zip
            }
            return nil
        }
    }
}
#endif
