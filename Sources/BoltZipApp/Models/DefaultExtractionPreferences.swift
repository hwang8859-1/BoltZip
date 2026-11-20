import BoltZipCore
import Foundation

enum DefaultExtractDestination: String, CaseIterable, Identifiable, Sendable {
    case sameFolder
    case downloads
    case ask

    var id: String { rawValue }

    func title(_ l: L10n) -> String {
        switch self {
        case .sameFolder: return l.extractDestSameFolder
        case .downloads: return l.extractDestDownloads
        case .ask: return l.extractDestAsk
        }
    }
}

enum DefaultExtractModePreference: String, CaseIterable, Identifiable, Sendable {
    case smart
    case subfolder

    var id: String { rawValue }

    var extractMode: ExtractMode {
        switch self {
        case .smart: return .smart
        case .subfolder: return .subfolder
        }
    }

    func title(_ l: L10n) -> String {
        switch self {
        case .smart: return l.extractModeSmart
        case .subfolder: return l.extractModeSubfolder
        }
    }
}
