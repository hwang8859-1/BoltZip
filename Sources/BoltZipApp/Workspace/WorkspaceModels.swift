import BoltZipCore
import Foundation

struct FolderTreeNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    var children: [FolderTreeNode]
    let fileCount: Int
}

enum SortColumn: String, CaseIterable, Identifiable {
    case name
    case uncompressedSize
    case compressedSize
    case ratio
    case method
    case modifiedDate

    var id: String { rawValue }
}

enum ActiveSheet: Identifiable {
    case createArchive([URL])
    case extractOptions(ExtractMode)
    case integrityReport(IntegrityReport)
    case benchmark
    case passwordPrompt(PasswordPurpose, wrongAttempt: Bool = false)
    case createFolder(parentFolder: String)
    case renamePath(oldPath: String, currentName: String)
    case entryProperties(ArchiveEntry)
    case editArchiveComment(current: String)
    case updateAvailable(UpdateReleaseInfo)
    case editEntryText(ArchiveTextDocument)

    var id: String {
        switch self {
        case .createArchive: return "createArchive"
        case .extractOptions: return "extractOptions"
        case .integrityReport: return "integrityReport"
        case .benchmark: return "benchmark"
        case .passwordPrompt: return "passwordPrompt"
        case .createFolder(let parent): return "createFolder-\(parent)"
        case .renamePath(let oldPath, _): return "rename-\(oldPath)"
        case .entryProperties(let entry): return "props-\(entry.id)"
        case .editArchiveComment: return "editArchiveComment"
        case .updateAvailable(let info): return "update-\(info.version)"
        case .editEntryText(let document): return "edit-entry-\(document.entryPath)"
        }
    }
}

enum PasswordPurpose: Sendable {
    case openArchive(
        url: URL,
        fromExternalFinder: Bool,
        isNestedOpening: Bool,
        initialFolder: String,
        encoding: FilenameEncodingOption
    )
    case returnToParent(frameID: UUID)
    case openNested(ArchiveEntry)
    case openNestedContents(ArchiveEntry, parentPassword: String?)
    case preview(ArchiveEntry)
    case extract(archiveURL: URL, options: ExtractOptions, trashArchiveOnCompletion: Bool)
    case testIntegrity(archiveURL: URL)
    case unlockForEdit(urls: [URL], targetFolder: String)
    case editText(ArchiveEntry)

    func prompt(for error: any Error) -> ActiveSheet? {
        switch error {
        case BoltZipError.passwordRequired: return .passwordPrompt(self)
        case BoltZipError.wrongPassword: return .passwordPrompt(self, wrongAttempt: true)
        default: return nil
        }
    }
}

struct ArchiveNavigationFrame: Identifiable, Sendable {
    let id = UUID()
    let archiveURL: URL
    let savedPassword: String?
    let encoding: FilenameEncodingOption
    let currentFolder: String
    let openedFromHome: Bool
    let nestedTempDirToCleanup: URL?
}

struct PendingBatchArchivePrompt: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct PendingDeleteConfirmation: Identifiable {
    let id = UUID()
    let paths: Set<String>
}

struct PendingExtractConflict: Identifiable {
    let id = UUID()
    let archiveURL: URL
    let options: ExtractOptions
    let destinationRoot: URL
    let conflictingNames: [String]
    let trashArchiveOnCompletion: Bool
}
