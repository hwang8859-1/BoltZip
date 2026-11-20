import BoltZipCore
import Darwin
import Foundation

func printUsage() {
    print("""
    BoltZip CLI v\(BoltZipVersion.current) (Open-Source macOS Compression Engine)
    Usage:
      boltzip a <output.zip|tar.zst|tar.gz|tar.xz|tar.bz2|tar.lz4|tar|7z> <input1> [input2...] [--algo deflate|zstd|bzip2|xz|lz4|store] [--level N] [--password PW] [--aes256|--zipcrypto] [--split MB] [--comment TEXT] [--threads auto|N] [--keep-junk] [--no-symlinks]
      boltzip x <archive> [dest_dir] [--mode smart|here|subfolder] [--overwrite overwrite|skip|rename] [--password PW] [--encoding auto|utf8|gb18030|big5|shiftjis|euckr|cp437] [--threads auto|N] [--keep-junk] [--no-symlinks]
      boltzip e <archive> [dest_dir] [--overwrite overwrite|skip|rename] [--password PW] [--encoding auto|utf8|gb18030|big5|shiftjis|euckr|cp437] [--threads auto|N] [--keep-junk]
      boltzip add <archive.zip> <input...> [--target folder/] [--algo deflate|zstd|bzip2|store] [--level N] [--password PW] [--aes256|--zipcrypto] [--comment TEXT]
      boltzip rm <archive.zip> <entryPath1> [entryPath2...]
      boltzip mkdir <archive.zip> <folderPath>
      boltzip mv <archive.zip> <oldPath> <newPath>
      boltzip l <archive> [--encoding auto|gb18030|big5|shiftjis|euckr|utf8|cp437] [--password PW] [--json]
      boltzip t <archive> [--password PW] [--threads auto|N] [--json]
      boltzip associate [--status] [--restore] [--include-iso]
      boltzip bench [--threads auto|N] [--json]
      boltzip engines
      boltzip version
    """)
}

func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
}

func makeTTYProgressHandler(enabled: Bool) -> (@Sendable (OperationProgress) -> Void)? {
    guard enabled && isatty(STDERR_FILENO) != 0 else { return nil }
    let progressLock = NSLock()
    return { prog in
        progressLock.lock()
        defer { progressLock.unlock() }
        let width = 24
        let frac = min(1.0, max(0.0, prog.fractionCompleted))
        let filled = Int((frac * Double(width)).rounded(.down))
        let bar = String(repeating: "#", count: filled) + String(repeating: "-", count: max(0, width - filled))
        let pct = Int((frac * 100.0).rounded())
        let item = prog.currentItem.isEmpty ? "" : " \(prog.currentItem)"
        let line = "\r\u{1B}[K[\(bar)] \(String(format: "%3d", pct))%\(item)"
        fputs(line, stderr)
        if frac >= 1.0 {
            fputs("\r\u{1B}[K", stderr)
        }
        fflush(stderr)
    }
}

func printJSON(_ object: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    if let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}
