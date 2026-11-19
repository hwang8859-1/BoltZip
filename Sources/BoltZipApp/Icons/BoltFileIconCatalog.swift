import BoltZipCore
import Foundation

/// Centralized UI symbol and document-icon resolution for archive entries and recent file rows.
enum BoltFileIconCatalog {
    static func sfSymbolName(for entry: ArchiveEntry) -> String {
        entry.isDirectory ? "folder.fill" : sfSymbolName(forFilename: entry.name)
    }

    static func sfSymbolName(forFilename filename: String) -> String {
        if BoltDocumentIconKind.resolve(forFilename: filename) != nil {
            return "doc.zipper"
        }

        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "c", "h", "cpp", "hpp", "m", "mm", "js", "ts", "jsx", "tsx", "py", "rb", "go", "rs", "java", "kt", "json", "xml", "yaml", "yml", "toml", "html", "css", "sh", "zsh":
            return "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "webp", "gif", "svg", "heic", "tiff", "bmp", "ico", "icns":
            return "photo"
        case "pdf":
            return "doc.richtext"
        case "md", "txt", "log", "rtf", "csv":
            return "doc.text"
        case "mp4", "mov", "mkv", "avi", "webm":
            return "film"
        case "mp3", "wav", "m4a", "flac", "aac", "ogg":
            return "waveform"
        case "dmg", "img":
            return "internaldrive"
        default:
            return "doc"
        }
    }

    static func documentIconKind(forFilename filename: String) -> BoltDocumentIconKind? {
        BoltDocumentIconKind.resolve(forFilename: filename)
    }
}
