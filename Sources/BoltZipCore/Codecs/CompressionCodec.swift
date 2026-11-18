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
        max(1, Int(bolt_active_cores()))
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

    public static func compress(
        data: Data,
        algorithm: CompressionAlgorithm,
        gzipContainer: Bool = false,
        level: Int? = nil,
        allowMultiThread: Bool = true,
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
        let allowMTFlag: Int32 = allowMultiThread ? 1 : 0
        let status = withExtendedLifetime(controlCtx) {
            let rawCtx = controlCtx.map { Unmanaged.passUnretained($0).toOpaque() }
            let cb: bolt_control_cb? = needsBridge ? boltCodecControlBridge : nil
            return data.withUnsafeBytes { rawBuf -> bolt_status_t in
                let ptr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                return bolt_compress_buffer_mt(mapAlgo(algorithm), container, lvl, ptr, data.count, &outBuf, allowMTFlag, cb, rawCtx)
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
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws -> Data {
        try controller?.checkpoint()
        if algorithm == .store {
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
                return bolt_decompress_buffer_ex(mapAlgo(algorithm), container, ptr, data.count, max(0, expectedSize), &outBuf, cb, rawCtx)
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
        level: Int? = nil
    ) throws {
        let lvl = Int32(level ?? algorithm.defaultLevel)
        let container = gzipContainer ? BOLT_CONTAINER_GZIP : BOLT_CONTAINER_RAW
        let status = bolt_compress_file(
            mapAlgo(algorithm),
            container,
            lvl,
            sourceURL.path,
            destinationURL.path,
            nil,
            nil
        )
        guard status.code == 0 else {
            let msg = withUnsafePointer(to: status.message) {
                $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            throw BoltZipError.compressionFailed(msg)
        }
    }

    public static func decompressFile(
        sourceURL: URL,
        destinationURL: URL,
        algorithm: CompressionAlgorithm,
        gzipContainer: Bool = false
    ) throws {
        let container = gzipContainer ? BOLT_CONTAINER_GZIP : BOLT_CONTAINER_RAW
        let status = bolt_decompress_file(
            mapAlgo(algorithm),
            container,
            sourceURL.path,
            destinationURL.path,
            nil,
            nil
        )
        guard status.code == 0 else {
            let msg = withUnsafePointer(to: status.message) {
                $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            throw BoltZipError.compressionFailed(msg)
        }
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
