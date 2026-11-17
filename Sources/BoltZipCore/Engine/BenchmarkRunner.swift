import Foundation

public enum BenchmarkRunner {
    public static func generateMixedSampleData(sizeBytes: Int = 2 * 1024 * 1024) -> Data {
        var buf = Data()
        buf.reserveCapacity(sizeBytes)
        var counter: UInt64 = 0x9E3779B97F4A7C15
        while buf.count < sizeBytes {
            counter = counter &* 6364136223846793005 &+ 1442695040888963407
            let tag = String(format: "%08llX", counter & 0xFFFFFFFF)
            let line = """
            {"id":"\(tag)","app":"BoltZip","os":"macOS 27.3","algo":"open-source","seq":\(buf.count),"note":"Windows Zip parity with AES-256 & GBK fix"}\n
            """
            buf.append(Data(line.utf8))
            // Mix deterministic non-repeating bytes every few records to mirror realistic files
            if (buf.count & 511) < 96 {
                var block = [UInt8](repeating: 0, count: 48)
                for idx in 0..<block.count {
                    counter = counter &* 2862933555777941757 &+ 3037000493
                    block[idx] = UInt8((counter >> 24) & 0xFF)
                }
                buf.append(contentsOf: block)
            }
        }
        return buf.prefix(sizeBytes)
    }

    public static func run(on sampleData: Data? = nil) throws -> [BenchmarkEntryResult] {
        let data = sampleData ?? generateMixedSampleData()
        let configs: [(CompressionAlgorithm, Int)] = [
            (.lz4, 3),
            (.zstd, 5),
            (.deflate, 6),
            (.bzip2, 6),
            (.xz, 5)
        ]

        var results: [BenchmarkEntryResult] = []
        let mb = Double(data.count) / (1024.0 * 1024.0)

        for (algo, level) in configs {
            let t0 = CFAbsoluteTimeGetCurrent()
            let compressed = try CompressionCodec.compress(data: data, algorithm: algo, gzipContainer: false, level: level)
            let compSec = max(0.0001, CFAbsoluteTimeGetCurrent() - t0)

            let t1 = CFAbsoluteTimeGetCurrent()
            let restored = try CompressionCodec.decompress(data: compressed, algorithm: algo, gzipContainer: false, expectedSize: data.count)
            let decompSec = max(0.0001, CFAbsoluteTimeGetCurrent() - t1)

            guard restored.count == data.count else {
                throw BoltZipError.corruptedEntry(entry: algo.shortName, detail: "Benchmark roundtrip size mismatch")
            }

            results.append(
                BenchmarkEntryResult(
                    id: "\(algo.rawValue)-\(level)",
                    algorithm: algo,
                    level: level,
                    originalBytes: data.count,
                    compressedBytes: compressed.count,
                    compressMBps: mb / compSec,
                    decompressMBps: mb / decompSec,
                    compressMs: compSec * 1000.0,
                    decompressMs: decompSec * 1000.0
                )
            )
        }
        return results
    }
}
