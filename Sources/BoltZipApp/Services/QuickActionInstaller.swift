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
        let distAppex = URL(fileURLWithPath: "/Users/xuyang/Codes/BoltZip/dist/BoltZip.app/Contents/PlugIns/BoltZipFinderSync.appex", isDirectory: true)
        if FileManager.default.fileExists(atPath: distAppex.path) {
            return distAppex
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
        // 1. Clean out legacy Services workflows so BoltZip lives cleanly in top-level "Bolt >"
        try uninstallLegacyWorkflows()

        guard let appex = appexURL else {
            throw NSError(
                domain: "BoltZip",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "未找到 BoltZipFinderSync.appex，请先运行 ./Scripts/build_app.sh 构建应用包"]
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
