import Foundation

private func splitVolumeURL(for archiveURL: URL, disk: Int) -> URL {
    archiveURL.deletingPathExtension().appendingPathExtension(String(format: "z%02d", disk + 1))
}

final class ZipVolumeAccessor: @unchecked Sendable {
    let mainURL: URL
    var volumeURLs: [URL] {
        ioLock.lock()
        defer { ioLock.unlock() }
        return allVolumes.isEmpty ? [mainURL] : allVolumes
    }
    private var handles: [Int: FileHandle] = [:]
    private var sizes: [Int: UInt64] = [:]
    private let ioLock = NSLock()

    static func isNumberedVolume(_ archiveURL: URL) -> Bool {
        let ext = archiveURL.pathExtension.lowercased()
        guard ext.hasPrefix("z"), Int(ext.dropFirst()) != nil else { return false }
        return (try? ZipReader(url: archiveURL).parseArchive(resolveNumberedVolume: false).totalDisks) != 1
    }

    init(archiveURL: URL, resolveNumberedVolume: Bool = true) throws {
        // If opened via .z01/.z02, locate matching .zip central file
        let resolvedMain: URL
        if resolveNumberedVolume && Self.isNumberedVolume(archiveURL) {
            resolvedMain = archiveURL.deletingPathExtension().appendingPathExtension("zip")
        } else {
            resolvedMain = archiveURL
        }
        guard FileManager.default.fileExists(atPath: resolvedMain.path) else {
            throw BoltZipError.missingSplitVolume(resolvedMain.lastPathComponent)
        }
        self.mainURL = resolvedMain
    }

    private var allVolumes: [URL] = []

    func configureVolumes(totalDisks: Int) throws {
        ioLock.lock()
        defer { ioLock.unlock() }
        var urls: [URL] = []
        if totalDisks > 1 {
            for disk in 0..<(totalDisks - 1) {
                let part = splitVolumeURL(for: mainURL, disk: disk)
                guard FileManager.default.fileExists(atPath: part.path) else {
                    throw BoltZipError.missingSplitVolume(part.lastPathComponent)
                }
                urls.append(part)
            }
        }
        urls.append(mainURL)
        if urls != allVolumes {
            // Before configuration, disk zero refers to the main file rather than the first split volume.
            if !(allVolumes.isEmpty && urls == [mainURL]) {
                closeHandlesLocked()
            }
            allVolumes = urls
        }
    }

    func closeAll() {
        ioLock.lock()
        defer { ioLock.unlock() }
        closeHandlesLocked()
    }

    private func closeHandlesLocked() {
        for handle in handles.values { try? handle.close() }
        handles.removeAll()
        sizes.removeAll()
    }

    deinit {
        closeAll()
    }

    private func handleLocked(forDisk disk: Int) throws -> (FileHandle, UInt64) {
        let list = allVolumes.isEmpty ? [mainURL] : allVolumes
        guard disk >= 0 && disk < list.count else {
            throw BoltZipError.missingSplitVolume("Disk #\(disk + 1)")
        }
        if let fh = handles[disk], let sz = sizes[disk] {
            return (fh, sz)
        }
        let url = list[disk]
        let fh = try FileHandle(forReadingFrom: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let sz = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        handles[disk] = fh
        sizes[disk] = sz
        return (fh, sz)
    }

    func mainFileSize() throws -> UInt64 {
        ioLock.lock()
        defer { ioLock.unlock() }
        let (_, sz) = try handleLocked(forDisk: max(0, allVolumes.count - 1))
        return sz
    }

    func totalAvailableBytes() throws -> UInt64 {
        ioLock.lock()
        defer { ioLock.unlock() }
        let list = allVolumes.isEmpty ? [mainURL] : allVolumes
        var total: UInt64 = 0
        for disk in 0..<list.count {
            let (_, sz) = try handleLocked(forDisk: disk)
            total = try ArchiveByteCount.checkedSum(total, sz)
        }
        return total
    }

    func readFromMainTail(length: Int) throws -> Data {
        ioLock.lock()
        defer { ioLock.unlock() }
        let disk = max(0, allVolumes.count - 1)
        let (fh, sz) = try handleLocked(forDisk: disk)
        let count = min(UInt64(length), sz)
        try fh.seek(toOffset: sz - count)
        return try fh.read(upToCount: Int(count)) ?? Data()
    }

    /// Reads `length` bytes starting at `(disk, offset)`, automatically spanning across split volumes if needed.
    func readSpanning(disk startDisk: Int, offset startOffset: UInt64, length: Int) throws -> (data: Data, endDisk: Int, endOffset: UInt64) {
        if length == 0 {
            return (Data(), startDisk, startOffset)
        }
        ioLock.lock()
        defer { ioLock.unlock() }
        var result = Data()
        result.reserveCapacity(length)
        var disk = startDisk
        var offset = startOffset
        var remaining = length

        while remaining > 0 {
            let (fh, diskSize) = try handleLocked(forDisk: disk)
            if offset >= diskSize {
                disk += 1
                offset = 0
                continue
            }
            let available = Int(min(UInt64(remaining), diskSize - offset))
            try fh.seek(toOffset: offset)
            let chunk = try fh.read(upToCount: available) ?? Data()
            if chunk.isEmpty {
                throw BoltZipError.invalidArchive("Unexpected EOF while reading ZIP disk #\(disk + 1)")
            }
            result.append(chunk)
            remaining -= chunk.count
            offset += UInt64(chunk.count)
            if remaining > 0 && offset >= diskSize {
                disk += 1
                offset = 0
            }
        }
        return (result, disk, offset)
    }

    func makeSpanningCursor(disk startDisk: Int, offset startOffset: UInt64, totalLength: UInt64) -> ZipSpanningCursor {
        ZipSpanningCursor(accessor: self, disk: startDisk, offset: startOffset, remaining: totalLength)
    }
}

final class ZipSpanningCursor {
    private let accessor: ZipVolumeAccessor
    private var disk: Int
    private var offset: UInt64
    private(set) var remaining: UInt64

    init(accessor: ZipVolumeAccessor, disk: Int, offset: UInt64, remaining: UInt64) {
        self.accessor = accessor
        self.disk = disk
        self.offset = offset
        self.remaining = remaining
    }

    func readNext(maxBytes: Int) throws -> Data {
        guard remaining > 0, maxBytes > 0 else { return Data() }
        let want = Int(min(UInt64(maxBytes), remaining))
        let (chunk, nextDisk, nextOffset) = try accessor.readSpanning(disk: disk, offset: offset, length: want)
        disk = nextDisk
        offset = nextOffset
        remaining -= UInt64(chunk.count)
        return chunk
    }
}

final class ZipVolumeSink {
    private let baseURL: URL
    private let splitLimit: UInt64?
    private(set) var currentDisk: Int = 0
    private(set) var currentOffset: UInt64 = 0
    private var currentHandle: FileHandle?
    private var createdFiles: [URL] = []
    private let tempPrefix: String

    init(outputURL: URL, splitLimit: UInt64?) throws {
        self.baseURL = outputURL
        self.splitLimit = (splitLimit ?? 0) >= 65536 ? splitLimit : nil
        self.tempPrefix = ".\(outputURL.lastPathComponent).boltzip.tmp.\(UUID().uuidString)"
        try openDisk(0)
        if self.splitLimit != nil {
            // Standard PKWARE split archive signature 0x08074B50 at start of disk 0
            var sig = Data()
            ZipBinary.appendUInt32LE(&sig, ZipSignature.dataDescriptor)
            try writeData(sig)
        }
    }

    private func tempURL(forDisk disk: Int) -> URL {
        let dir = baseURL.deletingLastPathComponent()
        return dir.appendingPathComponent("\(tempPrefix).part\(disk)")
    }

    private func finalURL(forDisk disk: Int, totalDisks: Int) -> URL {
        if disk == totalDisks - 1 {
            return baseURL
        }
        return splitVolumeURL(for: baseURL, disk: disk)
    }

    private func openDisk(_ disk: Int) throws {
        if let fh = currentHandle {
            try fh.close()
        }
        let url = tempURL(forDisk: disk)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let fh = try FileHandle(forWritingTo: url)
        currentHandle = fh
        currentDisk = disk
        currentOffset = 0
        createdFiles.append(url)
    }

    func ensureRoomBeforeHeader() throws {
        if let limit = splitLimit, currentOffset >= limit {
            try openDisk(currentDisk + 1)
        }
    }

    func writeData(_ data: Data) throws {
        guard !data.isEmpty else { return }
        guard let limit = splitLimit else {
            try currentHandle?.write(contentsOf: data)
            currentOffset += UInt64(data.count)
            return
        }

        var pos = 0
        while pos < data.count {
            if currentOffset >= limit {
                try openDisk(currentDisk + 1)
            }
            let room = Int(limit - currentOffset)
            let chunkLen = min(room, data.count - pos)
            let sub = data.subdata(in: pos..<(pos + chunkLen))
            try currentHandle?.write(contentsOf: sub)
            currentOffset += UInt64(chunkLen)
            pos += chunkLen
        }
    }

    func writeFile(
        from fileURL: URL,
        chunkSize: Int = BoltConcurrency.streamChunkSize,
        controller: ArchiveTaskController? = nil
    ) throws {
        let fh = try FileHandle(forReadingFrom: fileURL)
        defer { try? fh.close() }
        while true {
            try controller?.checkpoint()
            let chunk = try fh.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            try writeData(chunk)
        }
    }

    func finalizeAll() throws -> [URL] {
        try currentHandle?.close()
        currentHandle = nil

        let totalDisks = createdFiles.count
        let finalURLs = createdFiles.indices.map { finalURL(forDisk: $0, totalDisks: totalDisks) }
        try ArchiveOutputTransaction.publish(createdFiles, to: finalURLs)
        createdFiles.removeAll()
        return finalURLs
    }

    func abortCleanup() {
        try? currentHandle?.close()
        currentHandle = nil
        for url in createdFiles {
            try? FileManager.default.removeItem(at: url)
        }
        createdFiles.removeAll()
    }
}
