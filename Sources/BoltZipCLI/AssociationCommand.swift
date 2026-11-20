import BoltZipCore
import Darwin
import Foundation

func runAssociateCommand(flags: Set<String>) async -> Int32 {
    #if canImport(AppKit) && canImport(UniformTypeIdentifiers)
    if flags.contains("status") {
        let appPath = ArchiveAssociationService.resolveBoltZipAppURL()?.path ?? "Not found"
        let statuses = ArchiveAssociationService.currentStatuses()
        let maxExtLen = max(36, statuses.map { $0.group.extensionsSubtitle.count }.max() ?? 36)
        print("BoltZip.app: \(appPath)")
        for status in statuses {
            let marker = status.isBoltZipDefault ? "[BoltZip]" : "[\(status.currentAppName)]"
            let paddedID = status.group.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
            let paddedExts = status.group.extensionsSubtitle.padding(toLength: maxExtLen + 2, withPad: " ", startingAt: 0)
            print("  • \(paddedID) \(paddedExts) -> \(marker)")
        }
        return 0
    }

    let restore = flags.contains("restore")
    let targets: [ArchiveAssociationGroup] = (flags.contains("include-iso") || restore)
        ? ArchiveAssociationGroup.allCases
        : ArchiveAssociationGroup.commonArchiveGroups

    if let err = await ArchiveAssociationService.setDefault(for: targets, toBoltZip: !restore) {
        fputs("Error updating system file associations: \(err.localizedDescription)\n", stderr)
        return 1
    }

    let summary = restore
        ? "Restored system default handlers for \(targets.count) archive groups."
        : "Set BoltZip as system default handler for \(targets.count) archive groups."
    print(summary)
    for status in ArchiveAssociationService.currentStatuses() {
        let marker = status.isBoltZipDefault ? "BoltZip" : status.currentAppName
        let paddedID = status.group.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
        print("  • \(paddedID) -> \(marker)")
    }
    return 0
    #else
    fputs("Error: File association management requires macOS AppKit.\n", stderr)
    return 1
    #endif
}
