import Foundation

public enum ArchiveOperationError: LocalizedError, Sendable {
    case outputIsInput
    case extractionWouldReplaceSource(String)
    case outputIsDirectory(String)
    case inputChanged(String)
    case encryptionRequiresZIP
    case filenameEncryptionRequires7z
    case sevenZipEncryptionRequiresAES256
    case invalidSevenZipPassword
    case sevenZipEngineUnavailable
    case splitVolumesRequireZIP
    case singleStreamRequiresSingleRegularFile(String)
    case noRecoverableZipEntries
    case sevenZipSplitArchiveReadOnly
    case applicationNotFound

    // CLI fallback. The desktop app renders these structured errors through L10n.swift.
    public var errorDescription: String? {
        switch self {
        case .outputIsInput: return BoltCoreLocalization.archiveOutputIsInput
        case .extractionWouldReplaceSource(let name): return BoltCoreLocalization.extractionWouldReplaceSource(name)
        case .outputIsDirectory(let name): return BoltCoreLocalization.cannotReplaceDirectoryWithArchive(name)
        case .inputChanged(let path): return BoltCoreLocalization.inputChangedWhileArchiving(path)
        case .encryptionRequiresZIP: return BoltCoreLocalization.encryptionRequiresZIP
        case .filenameEncryptionRequires7z: return BoltCoreLocalization.filenameEncryptionRequires7z
        case .sevenZipEncryptionRequiresAES256: return BoltCoreLocalization.sevenZipEncryptionRequiresAES256
        case .invalidSevenZipPassword: return BoltCoreLocalization.invalidSevenZipPassword
        case .sevenZipEngineUnavailable: return BoltCoreLocalization.sevenZipEngineUnavailable
        case .splitVolumesRequireZIP: return BoltCoreLocalization.splitVolumesRequireZIP
        case .singleStreamRequiresSingleRegularFile(let formatName): return BoltCoreLocalization.singleStreamRequiresSingleRegularFile(formatName)
        case .noRecoverableZipEntries: return BoltCoreLocalization.noRecoverableZipEntries
        case .sevenZipSplitArchiveReadOnly: return BoltCoreLocalization.sevenZipSplitArchiveReadOnly
        case .applicationNotFound: return BoltCoreLocalization.applicationNotFoundForAssociation
        }
    }
}
