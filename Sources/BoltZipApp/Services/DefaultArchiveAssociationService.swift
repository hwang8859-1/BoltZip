import BoltZipCore
import Foundation

@MainActor
enum DefaultArchiveAssociationService {
    static func resolveBoltZipAppURL() -> URL? {
        let appexFallback = QuickActionInstaller.appexURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return ArchiveAssociationService.resolveBoltZipAppURL(fallbackURL: appexFallback)
    }

    static func currentStatuses() -> [ArchiveAssociationStatus] {
        ArchiveAssociationService.currentStatuses()
    }

    static func setDefault(for groups: [ArchiveAssociationGroup], toBoltZip: Bool) async -> String? {
        await ArchiveAssociationService.setDefault(
            for: groups,
            toBoltZip: toBoltZip,
            appURL: resolveBoltZipAppURL()
        )
    }
}
