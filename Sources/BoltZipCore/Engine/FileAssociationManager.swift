import CoreServices
import Foundation

public struct ArchiveFormatAssociation: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let extensions: [String]
    public let utis: [String]
    public let isCore: Bool

    public init(id: String, name: String, extensions: [String], utis: [String], isCore: Bool) {
        self.id = id
        self.name = name
        self.extensions = extensions
        self.utis = utis
        self.isCore = isCore
    }
}

public enum FileAssociationManager {
    public static let bundleID = "dev.boltzip.macos"

    public static let supportedFormats: [ArchiveFormatAssociation] = [
        ArchiveFormatAssociation(
            id: "zip",
            name: "ZIP",
            extensions: ["zip", "zipx", "cbz"],
            utis: ["public.zip-archive", "com.pkware.zip-archive"],
            isCore: true
        ),
        ArchiveFormatAssociation(
            id: "7z",
            name: "7-Zip",
            extensions: ["7z", "cb7"],
            utis: ["org.7-zip.7-zip-archive"],
            isCore: true
        ),
        ArchiveFormatAssociation(
            id: "rar",
            name: "RAR",
            extensions: ["rar", "cbr", "r00", "r01"],
            utis: ["com.rarlab.rar-archive"],
            isCore: true
        ),
        ArchiveFormatAssociation(
            id: "tar",
            name: "TAR",
            extensions: ["tar"],
            utis: ["public.tar-archive", "org.gnu.gnu-tar-archive"],
            isCore: true
        ),
        ArchiveFormatAssociation(
            id: "gz",
            name: "Gzip",
            extensions: ["gz", "tgz"],
            utis: ["org.gnu.gnu-zip-archive", "org.gnu.gnu-zip-tar-archive"],
            isCore: true
        ),
        ArchiveFormatAssociation(
            id: "bz2",
            name: "Bzip2",
            extensions: ["bz2", "tbz2"],
            utis: ["public.bzip2-archive", "public.tar-bzip2-archive"],
            isCore: true
        ),
        ArchiveFormatAssociation(
            id: "xz",
            name: "XZ",
            extensions: ["xz", "txz"],
            utis: ["org.tukaani.xz-archive", "org.tukaani.tar-xz-archive"],
            isCore: true
        ),
        ArchiveFormatAssociation(
            id: "zst",
            name: "Zstandard",
            extensions: ["zst", "tzst"],
            utis: ["com.facebook.zstandard-archive"],
            isCore: true
        ),
        ArchiveFormatAssociation(
            id: "lz4",
            name: "LZ4",
            extensions: ["lz4"],
            utis: ["org.lz4.lz4-archive"],
            isCore: false
        ),
        ArchiveFormatAssociation(
            id: "iso",
            name: "ISO",
            extensions: ["iso"],
            utis: ["public.iso-image"],
            isCore: false
        )
    ]

    public static func isDefaultHandlerForFormat(_ format: ArchiveFormatAssociation) -> Bool {
        for uti in format.utis {
            if let handler = LSCopyDefaultRoleHandlerForContentType(uti as CFString, .all)?.takeRetainedValue() as String? {
                if handler == bundleID {
                    return true
                }
            }
        }
        return false
    }

    public static func areAllCommonFormatsAssociated() -> Bool {
        for format in supportedFormats where format.isCore {
            if !isDefaultHandlerForFormat(format) {
                return false
            }
        }
        return true
    }

    @discardableResult
    public static func setDefaultHandler(for format: ArchiveFormatAssociation) -> Bool {
        var success = true
        for uti in format.utis {
            let status = LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, bundleID as CFString)
            if status != noErr {
                success = false
            }
        }
        return success
    }

    @discardableResult
    public static func associateAllCommonFormats() -> [String: Bool] {
        var results: [String: Bool] = [:]
        for format in supportedFormats where format.isCore {
            let ok = setDefaultHandler(for: format)
            results[format.id] = ok
        }
        return results
    }
}
