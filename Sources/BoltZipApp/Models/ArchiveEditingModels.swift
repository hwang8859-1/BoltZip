import BoltZipCore
import Foundation

struct ArchiveEditRequest: Sendable {
    let archiveURL: URL
    let operations: [ZipEditOperation]
    let options: CreateArchiveOptions
    let encoding: FilenameEncodingOption
    var temporaryDirectory: URL?
}

struct ArchiveTextDocument: Sendable {
    let archiveURL: URL
    let entryPath: String
    let text: String
    let encoding: String.Encoding
    let bom: Data
    let lineEnding: String
    let archiveModifiedDate: Date?
    let profile: ArchiveEntryCompressionProfile

    static func decode(_ data: Data) -> (String, String.Encoding, Data)? {
        let forms: [(Data, String.Encoding)] = [(Data([0xff, 0xfe]), .utf16LittleEndian),
            (Data([0xfe, 0xff]), .utf16BigEndian), (Data([0xef, 0xbb, 0xbf]), .utf8)]
        for (bom, encoding) in forms where data.starts(with: bom) {
            if let text = String(data: data.dropFirst(bom.count), encoding: encoding), !text.contains("\0") { return (text, encoding, bom) }
            return nil
        }
        guard let text = String(data: data, encoding: .utf8), !text.unicodeScalars.contains(where: { $0.value == 0 }) else { return nil }
        return (text, .utf8, Data())
    }

    func encoded(_ text: String) -> Data? {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if entryPath.uppercased() == "META-INF/MANIFEST.MF" {
            while !normalized.hasSuffix("\n\n") { normalized += "\n" }
        }
        guard let bytes = normalized.replacingOccurrences(of: "\n", with: lineEnding).data(using: encoding) else { return nil }
        return bom + bytes
    }
}
