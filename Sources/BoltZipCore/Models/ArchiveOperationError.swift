import Foundation

public enum ArchiveOperationError: LocalizedError, Sendable {
    case outputIsInput
    case outputIsDirectory(String)
    case inputChanged(String)
    case encryptionRequiresZIP
    case filenameEncryptionRequires7z
    case sevenZipEncryptionRequiresAES256
    case invalidSevenZipPassword
    case sevenZipEngineUnavailable
    case splitVolumesRequireZIP
    case applicationNotFound

    // CLI fallback. The desktop app renders these structured errors through L10n.swift.
    public var errorDescription: String? {
        switch self {
        case .outputIsInput: return BoltCoreLocalization.archiveOutputIsInput
        case .outputIsDirectory(let name): return BoltCoreLocalization.cannotReplaceDirectoryWithArchive(name)
        case .inputChanged(let path): return BoltCoreLocalization.inputChangedWhileArchiving(path)
        case .encryptionRequiresZIP: return BoltCoreLocalization.encryptionRequiresZIP
        case .filenameEncryptionRequires7z: return BoltCoreLocalization.filenameEncryptionRequires7z
        case .sevenZipEncryptionRequiresAES256: return BoltCoreLocalization.sevenZipEncryptionRequiresAES256
        case .invalidSevenZipPassword: return BoltCoreLocalization.invalidSevenZipPassword
        case .sevenZipEngineUnavailable: return BoltCoreLocalization.sevenZipEngineUnavailable
        case .splitVolumesRequireZIP: return BoltCoreLocalization.splitVolumesRequireZIP
        case .applicationNotFound: return BoltCoreLocalization.applicationNotFoundForAssociation
        }
    }
}
