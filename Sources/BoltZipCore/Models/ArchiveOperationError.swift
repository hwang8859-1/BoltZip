import Foundation

public enum ArchiveOperationError: LocalizedError, Sendable {
    case outputIsInput
    case outputIsDirectory(String)
    case inputChanged(String)
    case encryptionRequiresZIP
    case splitVolumesRequireZIP
    case applicationNotFound

    // CLI fallback. The desktop app renders these structured errors through L10n.swift.
    public var errorDescription: String? {
        switch self {
        case .outputIsInput: return BoltCoreLocalization.archiveOutputIsInput
        case .outputIsDirectory(let name): return BoltCoreLocalization.cannotReplaceDirectoryWithArchive(name)
        case .inputChanged(let path): return BoltCoreLocalization.inputChangedWhileArchiving(path)
        case .encryptionRequiresZIP: return BoltCoreLocalization.encryptionRequiresZIP
        case .splitVolumesRequireZIP: return BoltCoreLocalization.splitVolumesRequireZIP
        case .applicationNotFound: return BoltCoreLocalization.applicationNotFoundForAssociation
        }
    }
}
