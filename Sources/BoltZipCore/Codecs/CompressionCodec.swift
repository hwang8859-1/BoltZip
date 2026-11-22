import CBoltCompression
import Foundation

public struct CodecEngineInfo: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let license: String
}

private final class CCodecControlContext: @unchecked Sendable {
    let controller: ArchiveTaskController?
    let onProgress: ((UInt64, UInt64) -> Void)?

    init(controller: ArchiveTaskController?, onProgress: ((UInt64, UInt64) -> Void)?) {
        self.controller = controller
        self.onProgress = onProgress
    }
}

private let boltCodecControlBridge: bolt_control_cb = { bytesRead, totalBytes, rawCtx in
    guard let rawCtx else { return 0 }
    let ctx = Unmanaged<CCodecControlContext>.fromOpaque(rawCtx).takeUnretainedValue()
    if let controller = ctx.controller {
        do {
            try controller.checkpoint()
        } catch {
            return 1
        }
    }
    ctx.onProgress?(bytesRead, totalBytes)
    return 0
}

public enum CompressionCodec {
    public static var activeCoreCount: Int {
        BoltConcurrency.hardwareCoreCount
    }

    public static var effectiveWorkerCount: Int {
        BoltConcurrency.resolvedWorkerCount()
    }

    private static func mapAlgo(_ algo: CompressionAlgorithm) -> bolt_algo_t {
        switch algo {
        case .store: return BOLT_ALGO_STORE
        case .deflate: return BOLT_ALGO_DEFLATE
        case .bzip2: return BOLT_ALGO_BZIP2
        case .zstd: return BOLT_ALGO_ZSTD
        case .xz: return BOLT_ALGO_XZ
        case .lz4: return BOLT_ALGO_LZ4
        }
    }

    public static func crc32(_ data: Data, initial: UInt32 = 0) -> UInt32 {
        data.withUnsafeBytes { rawBuf in
            let ptr = rawBuf.bindMemory(to: UInt8.self).baseAddress
            return bolt_crc32(initial, ptr, data.count)
        }
    }

    public static func crc32File(
        at url: URL,
        chunkSize: Int = BoltConcurrency.streamChunkSize,
        controller: ArchiveTaskController? = nil
    ) throws -> UInt32 {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        var crc: UInt32 = 0
        while true {
            try controller?.checkpoint()
            let chunk = try fh.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            crc = crc32(chunk, initial: crc)
        }
        return crc
    }

    private static func throwIfCodecError(_ status: bolt_status_t) throws {
        if status.code == BOLT_STATUS_CANCELLED {
            throw BoltZipError.cancelled
        }
        guard status.code == 0 else {
            let msg = withUnsafePointer(to: status.message) {
                $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            throw BoltZipError.compressionFailed(msg)
        }
    }

    public static func compress(
        data: Data,
        algorithm: CompressionAlgorithm,
        gzipContainer: Bool = false,
        level: Int? = nil,
        allowMultiThread: Bool = true,
        workerCount: Int? = nil,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws -> Data {
        try controller?.checkpoint()
        if algorithm == .store {
            progress?(UInt64(data.count), UInt64(data.count))
            return data
        }
        let lvl = Int32(level ?? algorithm.defaultLevel)
        let container = gzipContainer ? BOLT_CONTAINER_GZIP : BOLT_CONTAINER_RAW
        var outBuf = bolt_buffer_t(data: nil, size: 0)
        defer { bolt_free_buffer(&outBuf) }

        let needsBridge = (controller != nil || progress != nil)
        let controlCtx = needsBridge ? CCodecControlContext(controller: controller, onProgress: progress) : nil
        let maxWorkers: Int32 = allowMultiThread
            ? Int32(BoltConcurrency.resolvedWorkerCount(override: workerCount))
            : 1
        let status = withExtendedLifetime(controlCtx) {
            let rawCtx = controlCtx.map { Unmanaged.passUnretained($0).toOpaque() }
            let cb: bolt_control_cb? = needsBridge ? boltCodecControlBridge : nil
            return data.withUnsafeBytes { rawBuf -> bolt_status_t in
                let ptr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                return bolt_compress_buffer_workers(mapAlgo(algorithm), container, lvl, ptr, data.count, &outBuf, maxWorkers, cb, rawCtx)
            }
        }
        if status.code == BOLT_STATUS_CANCELLED {
            throw BoltZipError.cancelled
        }
        guard status.code == 0 else {
            let msg = withUnsafePointer(to: status.message) {
                $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            throw BoltZipError.compressionFailed(msg)
        }
        guard let ptr = outBuf.data else { return Data() }
        return Data(bytes: ptr, count: outBuf.size)
    }

    public static func decompress(
        data: Data,
        algorithm: CompressionAlgorithm,
        gzipContainer: Bool = false,
        expectedSize: Int = 0,
        exactOutputSize: UInt64? = nil,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws -> Data {
        try controller?.checkpoint()
        if algorithm == .store {
            if let exactOutputSize, UInt64(data.count) != exactOutputSize {
                throw BoltZipError.invalidArchive("Decoded size does not match the declared entry size")
            }
            progress?(UInt64(data.count), UInt64(data.count))
            return data
        }
        let container = gzipContainer ? BOLT_CONTAINER_GZIP : BOLT_CONTAINER_RAW
        var outBuf = bolt_buffer_t(data: nil, size: 0)
        defer { bolt_free_buffer(&outBuf) }

        let needsBridge = (controller != nil || progress != nil)
        let controlCtx = needsBridge ? CCodecControlContext(controller: controller, onProgress: progress) : nil
        let status = withExtendedLifetime(controlCtx) {
            let rawCtx = controlCtx.map { Unmanaged.passUnretained($0).toOpaque() }
            let cb: bolt_control_cb? = needsBridge ? boltCodecControlBridge : nil
            return data.withUnsafeBytes { rawBuf -> bolt_status_t in
                let ptr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                return bolt_decompress_buffer_ex(mapAlgo(algorithm), container, ptr, data.count, max(0, expectedSize), exactOutputSize ?? UInt64.max, &outBuf, cb, rawCtx)
            }
        }
        if status.code == BOLT_STATUS_CANCELLED {
            throw BoltZipError.cancelled
        }
        guard status.code == 0 else {
            let msg = withUnsafePointer(to: status.message) {
                $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            throw BoltZipError.compressionFailed(msg)
        }
        guard let ptr = outBuf.data else { return Data() }
        return Data(bytes: ptr, count: outBuf.size)
    }

    public static func compressFile(
        sourceURL: URL,
        destinationURL: URL,
        algorithm: CompressionAlgorithm,
        gzipContainer: Bool = false,
        gzipOriginalFilename: String? = nil,
        gzipModifiedDate: Date? = nil,
        level: Int? = nil,
        allowMultiThread: Bool = true,
        workerCount: Int? = nil,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws {
        try controller?.checkpoint()
        let lvl = Int32(level ?? algorithm.defaultLevel)
        let container = gzipContainer ? BOLT_CONTAINER_GZIP : BOLT_CONTAINER_RAW
        let maxWorkers: Int32 = allowMultiThread
            ? Int32(BoltConcurrency.resolvedWorkerCount(override: workerCount))
            : 1
        let needsBridge = (controller != nil || progress != nil)
        let controlCtx = needsBridge ? CCodecControlContext(controller: controller, onProgress: progress) : nil
        let status = withExtendedLifetime(controlCtx) {
            let rawCtx = controlCtx.map { Unmanaged.passUnretained($0).toOpaque() }
            let cb: bolt_control_cb? = needsBridge ? boltCodecControlBridge : nil
            if algorithm == .deflate, gzipContainer, let name = gzipOriginalFilename, !name.isEmpty {
                let mtime = UInt32(max(0, Int64((gzipModifiedDate ?? Date()).timeIntervalSince1970)))
                return name.withCString { cname in
                    bolt_compress_gzip_file_named(
                        lvl,
                        sourceURL.path,
                        destinationURL.path,
                        cname,
                        mtime,
                        maxWorkers,
                        cb,
                        rawCtx
                    )
                }
            }
            return bolt_compress_file_workers(
                mapAlgo(algorithm),
                container,
                lvl,
                sourceURL.path,
                destinationURL.path,
                maxWorkers,
                cb,
                rawCtx
            )
        }
        try throwIfCodecError(status)
    }

    public static func decompressFile(
        sourceURL: URL,
        destinationURL: URL,
        algorithm: CompressionAlgorithm,
        gzipContainer: Bool = false,
        exactOutputSize: UInt64? = nil,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws {
        try controller?.checkpoint()
        let container = gzipContainer ? BOLT_CONTAINER_GZIP : BOLT_CONTAINER_RAW
        let needsBridge = (controller != nil || progress != nil)
        let controlCtx = needsBridge ? CCodecControlContext(controller: controller, onProgress: progress) : nil
        let status = withExtendedLifetime(controlCtx) {
            let rawCtx = controlCtx.map { Unmanaged.passUnretained($0).toOpaque() }
            let cb: bolt_control_cb? = needsBridge ? boltCodecControlBridge : nil
            return bolt_decompress_file_ex(
                mapAlgo(algorithm),
                container,
                sourceURL.path,
                destinationURL.path,
                exactOutputSize ?? UInt64.max,
                cb,
                rawCtx
            )
        }
        try throwIfCodecError(status)
    }

    public static func decompressPrefix(
        of sourceURL: URL,
        algorithm: CompressionAlgorithm,
        gzipContainer: Bool = false,
        maxBytes: Int = 512
    ) throws -> Data {
        let container = gzipContainer ? BOLT_CONTAINER_GZIP : BOLT_CONTAINER_RAW
        var outBuf = bolt_buffer_t(data: nil, size: 0)
        defer { bolt_free_buffer(&outBuf) }
        let status = bolt_decompress_file_prefix(
            mapAlgo(algorithm),
            container,
            sourceURL.path,
            max(0, maxBytes),
            &outBuf
        )
        try throwIfCodecError(status)
        guard let ptr = outBuf.data, outBuf.size > 0 else { return Data() }
        return Data(bytes: ptr, count: outBuf.size)
    }

    public static func verifyFile(
        sourceURL: URL,
        algorithm: CompressionAlgorithm,
        gzipContainer: Bool = false,
        exactOutputSize: UInt64? = nil,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws -> (crc32: UInt32, uncompressedSize: UInt64) {
        try controller?.checkpoint()
        let container = gzipContainer ? BOLT_CONTAINER_GZIP : BOLT_CONTAINER_RAW
        let needsBridge = (controller != nil || progress != nil)
        let controlCtx = needsBridge ? CCodecControlContext(controller: controller, onProgress: progress) : nil
        var crcOut: UInt32 = 0
        var sizeOut: UInt64 = 0
        let status = withExtendedLifetime(controlCtx) {
            let rawCtx = controlCtx.map { Unmanaged.passUnretained($0).toOpaque() }
            let cb: bolt_control_cb? = needsBridge ? boltCodecControlBridge : nil
            return bolt_verify_file(
                mapAlgo(algorithm),
                container,
                sourceURL.path,
                &crcOut,
                &sizeOut,
                exactOutputSize ?? UInt64.max,
                cb,
                rawCtx
            )
        }
        try throwIfCodecError(status)
        return (crcOut, sizeOut)
    }

    public static func engineVersions() -> [CodecEngineInfo] {
        [
            CodecEngineInfo(id: "zlib", name: "zlib (DEFLATE / Gzip)", version: String(cString: bolt_zlib_version()), license: "zlib License"),
            CodecEngineInfo(id: "zstd", name: "Zstandard (libzstd)", version: String(cString: bolt_zstd_version()), license: "BSD-3-Clause"),
            CodecEngineInfo(id: "xz", name: "XZ Utils (liblzma / LZMA2)", version: String(cString: bolt_lzma_version()), license: "0BSD / Public Domain"),
            CodecEngineInfo(id: "bzip2", name: "bzip2 (libbz2)", version: String(cString: bolt_bz2_version()), license: "bzip2 License"),
            CodecEngineInfo(id: "lz4", name: "LZ4 (lz4frame)", version: String(cString: bolt_lz4_version()), license: "BSD-2-Clause"),
            CodecEngineInfo(id: "libarchive", name: "libarchive (RAR / RAR5 / 7z / ISO)", version: String(cString: bolt_libarchive_version()), license: "BSD-2-Clause")
        ]
    }
}
