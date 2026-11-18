import BoltZipCore
import FinderSync
import Foundation

enum QuickActionInstaller {
    static let extensionBundleID = "dev.boltzip.macos.FinderSync"

    static var servicesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services", isDirectory: true)
    }

    static var appexURL: URL? {
        let embedded = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/BoltZipFinderSync.appex", isDirectory: true)
        if FileManager.default.fileExists(atPath: embedded.path) {
            return embedded
        }

        // Walk up from current binary/working dir so `swift run` in development finds dist/BoltZip.app dynamically
        let roots: [URL] = [
            Bundle.main.bundleURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        ]
        for base in roots {
            var cur = base
            for _ in 0..<6 {
                let candidate = cur.appendingPathComponent("dist/BoltZip.app/Contents/PlugIns/BoltZipFinderSync.appex", isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
                let parent = cur.deletingLastPathComponent()
                if parent.path == cur.path { break }
                cur = parent
            }
        }

        let installedApp = URL(fileURLWithPath: "/Applications/BoltZip.app/Contents/PlugIns/BoltZipFinderSync.appex", isDirectory: true)
        if FileManager.default.fileExists(atPath: installedApp.path) {
            return installedApp
        }
        return nil
    }

    static func isExtensionEnabled() -> Bool {
        if FIFinderSyncController.isExtensionEnabled {
            return true
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        proc.arguments = ["-m", "-i", extensionBundleID]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        proc.waitUntilExit()
        return out.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("+") }
    }

    static func installTopLevelFinderMenu() throws -> Bool {
        try uninstallLegacyWorkflows()

        guard let appex = appexURL else {
            throw NSError(
                domain: "BoltZip",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: BoltCoreLocalization.t(
                    "未找到 BoltZipFinderSync.appex，请先运行 ./Scripts/build_app.sh 构建应用包",
                    "找不到 BoltZipFinderSync.appex，請先執行 ./Scripts/build_app.sh 建置應用程式套件",
                    "BoltZipFinderSync.appex not found. Please run ./Scripts/build_app.sh first.",
                    "BoltZipFinderSync.appex が見つかりません。先に ./Scripts/build_app.sh を実行してください。"
                )]
            )
        }

        let appBundle = appex.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        _ = runTool("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", appBundle.path])
        _ = runTool("/usr/bin/pluginkit", ["-a", appex.path])
        _ = runTool("/usr/bin/pluginkit", ["-e", "use", "-i", extensionBundleID])

        return isExtensionEnabled()
    }

    static func disableTopLevelFinderMenu() {
        _ = runTool("/usr/bin/pluginkit", ["-e", "ignore", "-i", extensionBundleID])
    }

    @MainActor
    static func openSystemExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    static func uninstallLegacyWorkflows() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: servicesDirectory.path) else { return }
        let contents = try fm.contentsOfDirectory(at: servicesDirectory, includingPropertiesForKeys: nil)
        var removed = false
        for url in contents where url.pathExtension == "workflow" && url.lastPathComponent.hasPrefix("BoltZip") {
            try fm.removeItem(at: url)
            removed = true
        }
        if removed {
            _ = runTool("/System/Library/CoreServices/pbs", ["-update"])
        }
    }

    @discardableResult
    private static func runTool(_ path: String, _ args: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus
        } catch {
            return -1
        }
    }
}
