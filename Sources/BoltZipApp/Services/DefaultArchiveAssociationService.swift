import AppKit
import Foundation
import UniformTypeIdentifiers

enum ArchiveAssociationGroup: String, CaseIterable, Identifiable, Sendable {
    case zip
    case rar
    case sevenZip
    case tar
    case singleStreams
    case cabXar
    case iso

    var id: String { rawValue }

    var extensionsSubtitle: String {
        switch self {
        case .zip: return ".zip / .zipx / .z01"
        case .rar: return ".rar / .r00"
        case .sevenZip: return ".7z"
        case .tar: return ".tar / .tgz / .tar.zst / .txz / .tbz2"
        case .singleStreams: return ".gz / .zst / .xz / .bz2 / .lz4"
        case .cabXar: return ".cab / .xar"
        case .iso: return ".iso"
        }
    }

    /// Standard archive formats targeted by the one-click "Set All as Default" action (keeps ISO mounted by macOS DiskImageMounter unless user explicitly toggles ISO).
    static var commonArchiveGroups: [ArchiveAssociationGroup] {
        [.zip, .rar, .sevenZip, .tar, .singleStreams, .cabXar]
    }

    var primaryUTType: UTType? {
        utTypes.first
    }

    var fallbackExtensions: [String] {
        switch self {
        case .zip: return ["zip"]
        case .rar: return ["rar"]
        case .sevenZip: return ["7z"]
        case .tar: return ["tar", "tgz", "txz", "tbz2"]
        case .singleStreams: return ["gz", "bz2", "zst", "xz", "lz4"]
        case .cabXar: return ["cab", "xar"]
        case .iso: return ["iso"]
        }
    }

    var utTypes: [UTType] {
        let rawIDs: [String]
        switch self {
        case .zip:
            rawIDs = ["public.zip-archive", "com.pkware.zip-archive"]
        case .rar:
            rawIDs = ["com.rarlab.rar-archive"]
        case .sevenZip:
            rawIDs = ["org.7-zip.7-zip-archive"]
        case .tar:
            rawIDs = [
                "public.tar-archive",
                "org.gnu.gnu-zip-tar-archive",
                "com.facebook.zstandard-tar-archive",
                "org.tukaani.tar-xz-archive",
                "public.tar-bzip2-archive",
                "public.lz4-tar-archive"
            ]
        case .singleStreams:
            rawIDs = [
                "org.gnu.gnu-zip-archive",
                "com.facebook.zstandard-archive",
                "org.tukaani.xz-archive",
                "public.bzip2-archive",
                "org.lz4.lz4-archive",
                "public.lz4-archive"
            ]
        case .cabXar:
            rawIDs = ["com.microsoft.cab", "com.microsoft.cab-archive", "com.apple.xar-archive"]
        case .iso:
            rawIDs = ["public.iso-image"]
        }
        let declared = rawIDs.compactMap { UTType($0) }
        if !declared.isEmpty {
            return declared
        }
        return fallbackExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    var systemDefaultAppURL: URL? {
        let candidates: [String]
        switch self {
        case .iso:
            candidates = [
                "/System/Library/CoreServices/Applications/DiskImageMounter.app",
                "/System/Library/CoreServices/DiskImageMounter.app"
            ]
        default:
            candidates = [
                "/System/Library/CoreServices/Applications/Archive Utility.app",
                "/System/Library/CoreServices/Archive Utility.app"
            ]
        }
        return candidates.map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

struct ArchiveAssociationStatus: Identifiable, Sendable {
    let group: ArchiveAssociationGroup
    let isBoltZipDefault: Bool
    let currentAppName: String

    var id: String { group.id }
}

@MainActor
enum DefaultArchiveAssociationService {
    static let boltZipBundleID = "dev.boltzip.macos"

    static func resolveBoltZipAppURL() -> URL? {
        if Bundle.main.bundleURL.pathExtension.lowercased() == "app",
           Bundle.main.bundleIdentifier == boltZipBundleID {
            return Bundle.main.bundleURL
        }
        if let appex = QuickActionInstaller.appexURL {
            return appex
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        let installed = URL(fileURLWithPath: "/Applications/BoltZip.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: installed.path) {
            return installed
        }
        return nil
    }

    static func currentStatuses() -> [ArchiveAssociationStatus] {
        ArchiveAssociationGroup.allCases.map { group in
            guard let ut = group.primaryUTType,
                  let appURL = NSWorkspace.shared.urlForApplication(toOpen: ut) else {
                return ArchiveAssociationStatus(group: group, isBoltZipDefault: false, currentAppName: "—")
            }
            let bundleID = Bundle(url: appURL)?.bundleIdentifier
            let isBolt = (bundleID == boltZipBundleID)
                || appURL.deletingPathExtension().lastPathComponent.caseInsensitiveCompare("BoltZip") == .orderedSame
            let displayName = FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
            return ArchiveAssociationStatus(group: group, isBoltZipDefault: isBolt, currentAppName: displayName)
        }
    }

    static func setDefault(for groups: [ArchiveAssociationGroup], toBoltZip: Bool) async -> String? {
        let workspace = NSWorkspace.shared
        if toBoltZip {
            guard let appURL = resolveBoltZipAppURL() else {
                return "未找到 BoltZip.app，请先运行 ./Scripts/build_app.sh 构建应用包"
            }
            registerBundleWithLaunchServices(appURL)

            var firstError: String?
            for group in groups {
                for ut in group.utTypes {
                    do {
                        try await workspace.setDefaultApplication(at: appURL, toOpen: ut)
                    } catch {
                        if firstError == nil {
                            firstError = error.localizedDescription
                        }
                    }
                }
            }
            return firstError
        } else {
            var firstError: String?
            for group in groups {
                guard let sysURL = group.systemDefaultAppURL else { continue }
                for ut in group.utTypes {
                    do {
                        try await workspace.setDefaultApplication(at: sysURL, toOpen: ut)
                    } catch {
                        if firstError == nil {
                            firstError = error.localizedDescription
                        }
                    }
                }
            }
            return firstError
        }
    }

    private static func registerBundleWithLaunchServices(_ appURL: URL) {
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        guard FileManager.default.isExecutableFile(atPath: lsregister) else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: lsregister)
        proc.arguments = ["-f", appURL.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }
}
