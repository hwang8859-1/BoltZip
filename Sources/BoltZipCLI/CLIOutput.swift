import BoltZipCore
import Darwin
import Foundation

func printUsage() {
    print("""
    BoltZip CLI v\(BoltZipVersion.current) (Open-Source macOS Compression Engine)
    Usage:
      boltzip a <output.zip|tar.zst|tar.gz|tar.xz|tar.bz2|tar.lz4|tar|7z|gz|xz|dir> <input1> [input2...] [--algo deflate|zstd|bzip2|xz|lz4|store] [--level N] [--exclude PATTERN] [--password PW|--password-stdin|--ask-password] [--aes256|--zipcrypto] [--encrypt-filenames] [--split MB] [--comment TEXT] [--threads auto|N] [--keep-junk] [--no-symlinks]
      boltzip x <archive> [dest_dir] [--mode smart|here|subfolder] [--overwrite overwrite|skip|rename] [--password PW|--password-stdin|--ask-password] [--encoding auto|utf8|gb18030|big5|shiftjis|euckr|cp437] [--threads auto|N] [--keep-junk] [--no-symlinks]
      boltzip e <archive> [dest_dir] [--overwrite overwrite|skip|rename] [--password PW|--password-stdin|--ask-password] [--encoding auto|utf8|gb18030|big5|shiftjis|euckr|cp437] [--threads auto|N] [--keep-junk]
      boltzip add <archive.zip|.7z> <input...> [--target folder/] [--algo ...] [--level N] [--exclude PATTERN] [--password PW|--password-stdin|--ask-password] [--aes256|--zipcrypto] [--encrypt-filenames] [--comment TEXT]
      boltzip rm <archive.zip|.7z> <entryPath1> [entryPath2...] [--password PW|--password-stdin|--ask-password]
      boltzip mkdir <archive.zip|.7z> <folderPath> [--password PW|--password-stdin|--ask-password]
      boltzip mv <archive.zip|.7z> <oldPath> <newPath> [--password PW|--password-stdin|--ask-password]
      boltzip recover <damaged.zip> <output.zip> [--password PW|--password-stdin|--ask-password] [--encoding ...] [--json]
      boltzip l <archive> [--encoding ...] [--password PW|--password-stdin|--ask-password] [--json]
      boltzip t <archive> [--password PW|--password-stdin|--ask-password] [--threads auto|N] [--json]
      boltzip associate [--status] [--restore] [--include-iso]
      boltzip bench [--threads auto|N] [--json]
      boltzip mcp
      boltzip engines
      boltzip version

    --encrypt-filenames requires 7z output and an AES-256 password.
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
