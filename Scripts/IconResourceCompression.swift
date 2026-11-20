import Foundation

/// Recompresses generated PNG resources before hashing and signing the bundle.
struct IconResourceCompression {
    private static let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])
    private let pngcrush: URL?
    private let inputPNG: URL
    private let outputPNG: URL

    init(workDirectory: URL) {
        let finder = Process()
        finder.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        finder.arguments = ["--find", "pngcrush"]
        finder.standardError = FileHandle.nullDevice
        let output = Pipe()
        finder.standardOutput = output
        if (try? finder.run()) != nil {
            let path = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            finder.waitUntilExit()
            pngcrush = finder.terminationStatus == 0 && !path.isEmpty ? URL(fileURLWithPath: path) : nil
        } else {
            pngcrush = nil
        }
        if pngcrush == nil {
            fputs("Warning: pngcrush unavailable; keeping the generated PNG compression.\n", stderr)
        }
        inputPNG = workDirectory.appendingPathComponent("icon-input.png")
        outputPNG = workDirectory.appendingPathComponent("icon-output.png")
    }

    func compactICNS(at url: URL) throws {
        guard pngcrush != nil else { return }
        let source = try Data(contentsOf: url)
        guard source.count >= 8, source.prefix(4) == Data("icns".utf8),
              readLength(in: source, at: 4) == source.count else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
        }

        var chunks = Data()
        var optimizedPNGs: [Data: Data] = [:]
        var offset = 8
        while offset < source.count {
            guard source.count - offset >= 8 else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
            }
            let type = source.subdata(in: offset..<(offset + 4))
            let length = readLength(in: source, at: offset + 4)
            guard length >= 8, length <= source.count - offset else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
            }
            let payload = source.subdata(in: (offset + 8)..<(offset + length))
            offset += length
            let output: Data
            if payload.starts(with: Self.pngSignature) {
                if let cached = optimizedPNGs[payload] {
                    output = cached
                } else {
                    output = try optimizePNG(payload)
                    optimizedPNGs[payload] = output
                }
            } else {
                output = payload
            }
            chunks.append(type)
            appendLength(output.count + 8, to: &chunks)
            chunks.append(output)
        }

        var result = Data("icns".utf8)
        appendLength(chunks.count + 8, to: &result)
        result.append(chunks)
        try result.write(to: url, options: .atomic)
    }

    func optimizePNG(_ source: Data) throws -> Data {
        guard let pngcrush else { return source }
        try source.write(to: inputPNG)
        if FileManager.default.fileExists(atPath: outputPNG.path) {
            try FileManager.default.removeItem(at: outputPNG)
        }

        let process = Process()
        process.executableURL = pngcrush
        process.arguments = ["-q", inputPNG.path, outputPNG.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: outputPNG])
        }

        let originalChunks = try pngChunks(in: source)
        let optimizedChunks = try pngChunks(in: Data(contentsOf: outputPNG))
        // Keep the source color profile, image metadata and bit depth. Only replace IDAT chunks.
        guard let header = originalChunks.first, header.type == "IHDR",
              optimizedChunks.first?.bytes == header.bytes else {
            return source
        }
        let imageData = optimizedChunks.filter { $0.type == "IDAT" }
        guard !imageData.isEmpty else { return source }

        var result = Self.pngSignature
        var hasReplacedImageData = false
        for chunk in originalChunks {
            if chunk.type == "IDAT" {
                guard !hasReplacedImageData else { continue }
                for piece in imageData { result.append(piece.bytes) }
                hasReplacedImageData = true
            } else {
                result.append(chunk.bytes)
            }
        }
        return result.count < source.count ? result : source
    }

    private func pngChunks(in data: Data) throws -> [(type: String, bytes: Data)] {
        guard data.starts(with: Self.pngSignature) else { throw CocoaError(.fileReadCorruptFile) }
        var chunks: [(String, Data)] = []
        var offset = Self.pngSignature.count
        while offset < data.count {
            guard data.count - offset >= 12 else { throw CocoaError(.fileReadCorruptFile) }
            let length = readLength(in: data, at: offset)
            guard length <= data.count - offset - 12 else { throw CocoaError(.fileReadCorruptFile) }
            let end = offset + length + 12
            let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            chunks.append((type, data.subdata(in: offset..<end)))
            offset = end
        }
        return chunks
    }

    private func readLength(in data: Data, at offset: Int) -> Int {
        data.withUnsafeBytes { bytes in
            Int(UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
        }
    }

    private func appendLength(_ value: Int, to data: inout Data) {
        var length = UInt32(value).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
    }
}
