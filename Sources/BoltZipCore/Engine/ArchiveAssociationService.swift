#if canImport(AppKit) && canImport(UniformTypeIdentifiers)
import AppKit
import CoreServices
import Darwin
import Foundation
import UniformTypeIdentifiers

public enum ArchiveAssociationGroup: String, CaseIterable, Identifiable, Sendable {
    case zip
    case rar
    case sevenZip
    case tar
    case singleStreams
    case cabXar
    case iso

    public var id: String { rawValue }

    public var extensionsSubtitle: String {
        switch self {
        case .zip: return ".zip / .zipx / .z01 / .cbz"
        case .rar: return ".rar / .r00 / .cbr"
        case .sevenZip: return ".7z / .7z.001 / .cb7"
        case .tar: return ".tar / .tgz / .tar.zst / .txz / .tbz2"
        case .singleStreams: return ".gz / .zst / .xz / .bz2 / .lz4"
        case .cabXar: return ".cab / .xar"
        case .iso: return ".iso"
        }
    }

    /// Standard archive formats targeted by the one-click "Set All as Default" action
    /// (preserves macOS DiskImageMounter for `.iso` unless explicitly toggled).
    public static var commonArchiveGroups: [ArchiveAssociationGroup] {
        [.zip, .rar, .sevenZip, .tar, .singleStreams, .cabXar]
    }

    public var documentIconKind: BoltDocumentIconKind {
        switch self {
        case .zip: return .zip
        case .rar: return .rar
        case .sevenZip: return .sevenZip
        case .tar: return .tar
        case .singleStreams: return .zst
        case .cabXar: return .cab
        case .iso: return .iso
        }
    }

    public var primaryUTType: UTType? {
        utTypes.first
    }

    public var utTypeIdentifiers: [String] {
        switch self {
        case .zip:
            return ["public.zip-archive", "com.pkware.zip-archive", "com.winzip.zipx-archive"]
        case .rar:
            return ["com.rarlab.rar-archive"]
        case .sevenZip:
            return ["org.7-zip.7-zip-archive"]
        case .tar:
            return [
                "public.tar-archive",
                "org.gnu.gnu-zip-tar-archive",
                "com.facebook.zstandard-tar-archive",
                "org.tukaani.tar-xz-archive",
                "public.tar-bzip2-archive",
                "public.lz4-tar-archive"
            ]
        case .singleStreams:
            return [
                "org.gnu.gnu-zip-archive",
                "com.facebook.zstandard-archive",
                "org.tukaani.xz-archive",
                "org.tukaani.lzma-archive",
                "public.bzip2-archive",
                "org.lz4.lz4-archive",
                "public.lz4-archive"
            ]
        case .cabXar:
            return ["com.microsoft.cab", "com.microsoft.cab-archive", "com.apple.xar-archive"]
        case .iso:
            return ["public.iso-image"]
        }
    }

    public var fallbackExtensions: [String] {
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

    public var utTypes: [UTType] {
        let declared = utTypeIdentifiers.compactMap { UTType($0) }.filter { !$0.isDynamic }
        if !declared.isEmpty {
            return declared
        }
        let fallback = fallbackExtensions.compactMap { UTType(filenameExtension: $0) }
        let nonDynamicFallback = fallback.filter { !$0.isDynamic }
        return nonDynamicFallback.isEmpty ? fallback : nonDynamicFallback
    }

    public var systemDefaultAppURL: URL? {
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

public struct ArchiveAssociationStatus: Identifiable, Sendable {
    public let group: ArchiveAssociationGroup
    public let isBoltZipDefault: Bool
    public let currentAppName: String

    public var id: String { group.id }
}

public enum ArchiveAssociationService {
    public static let boltZipBundleID = "dev.boltzip.macos"

    public static func resolveBoltZipAppURL(fallbackURL: URL? = nil) -> URL? {
        if let fallbackURL, FileManager.default.fileExists(atPath: fallbackURL.path) {
            return fallbackURL
        }

        if Bundle.main.bundleURL.pathExtension.lowercased() == "app",
           Bundle.main.bundleIdentifier == boltZipBundleID {
            return Bundle.main.bundleURL
        }

        var seedURLs: [URL] = [Bundle.main.bundleURL]
        if let execURL = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            seedURLs.append(execURL)
        }
        if let arg0 = CommandLine.arguments.first {
            seedURLs.append(URL(fileURLWithPath: arg0).resolvingSymlinksInPath())
        }

        for seed in seedURLs {
            if let enclosing = enclosingBoltZipApp(startingFrom: seed) {
                return enclosing
            }
        }

        let installedPaths = [
            "/Applications/BoltZip.app",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/BoltZip.app", isDirectory: true).path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("dist/BoltZip.app", isDirectory: true).path
        ]
        for path in installedPaths where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: boltZipBundleID),
           FileManager.default.fileExists(atPath: registered.path) {
            return registered
        }

        return nil
    }

    public static func currentStatuses() -> [ArchiveAssociationStatus] {
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

    public static func setDefault(
        for groups: [ArchiveAssociationGroup],
        toBoltZip: Bool,
        appURL: URL? = nil
    ) async -> (any Error)? {
        let workspace = NSWorkspace.shared
        var changed = false
        var refreshedApps: Set<URL> = []
        if toBoltZip {
            guard let resolvedAppURL = appURL ?? resolveBoltZipAppURL() else {
                return ArchiveOperationError.applicationNotFound
            }
            registerBundleWithLaunchServices(resolvedAppURL)

            var firstError: (any Error)?
            for group in groups {
                for ut in group.utTypes {
                    do {
                        try await workspace.setDefaultApplication(at: resolvedAppURL, toOpen: ut)
                        changed = true
                        refreshedApps.insert(resolvedAppURL)
                    } catch {
                        if firstError == nil {
                            firstError = error
                        }
                    }
                }
            }
            if changed { await refreshDocumentIcons(for: refreshedApps) }
            return firstError
        } else {
            var firstError: (any Error)?
            for group in groups {
                guard let sysURL = group.systemDefaultAppURL else { continue }
                for ut in group.utTypes {
                    do {
                        try await workspace.setDefaultApplication(at: sysURL, toOpen: ut)
                        changed = true
                        refreshedApps.insert(sysURL)
                    } catch {
                        if firstError == nil {
                            firstError = error
                        }
                    }
                }
            }
            if changed { await refreshDocumentIcons(for: refreshedApps) }
            return firstError
        }
    }

    private static func enclosingBoltZipApp(startingFrom url: URL) -> URL? {
        var cursor = url.standardizedFileURL
        while cursor.path != "/" {
            if cursor.pathExtension.lowercased() == "app" {
                let bundleID = Bundle(url: cursor)?.bundleIdentifier
                let isBoltName = cursor.deletingPathExtension().lastPathComponent
                    .caseInsensitiveCompare("BoltZip") == .orderedSame
                if bundleID == boltZipBundleID || isBoltName {
                    return cursor
                }
            }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }
        return nil
    }

    private static func registerBundleWithLaunchServices(_ appURL: URL) {
        LSRegisterURL(appURL as CFURL, true)
    }

    private static func refreshDocumentIcons(for appURLs: Set<URL>) async {
        await Task.detached(priority: .utility) {
            for appURL in appURLs { registerBundleWithLaunchServices(appURL) }
            // IconServices persists images across default-handler changes. Restart only the
            // current user's disposable agent, once per batch; never touch its system store.
            guard getuid() != 0 else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["-KILL", "-u", NSUserName(), "iconservicesagent"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Association already succeeded; a denied refresh must not report a false failure.
                return
            }
        }.value
    }
}

extension ArchiveFormat {
    public var documentIconKind: BoltDocumentIconKind {
        switch self {
        case .zip: return .zip
        case .rar: return .rar
        case .sevenZip: return .sevenZip
        case .tar: return .tar
        case .tarGz: return .tgz
        case .tarZst: return .tzst
        case .tarXz: return .txz
        case .tarBz2: return .tbz2
        case .tarLz4: return .tlz4
        case .gz: return .gz
        case .zst: return .zst
        case .xz: return .xz
        case .bz2: return .bz2
        case .lz4: return .lz4
        case .iso: return .iso
        case .cab: return .cab
        case .xar: return .xar
        }
    }
}
#endif
