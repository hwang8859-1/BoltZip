import Darwin
import Foundation
import os

enum SevenZipCommand {
    struct Result {
        let status: Int32
        let stdout: Data
        let stderr: Data
    }

    static func validatePassword(_ password: String) throws {
        guard !password.isEmpty, !password.utf8.contains(where: { $0 == 0 || $0 == 10 || $0 == 13 }) else {
            throw ArchiveOperationError.invalidSevenZipPassword
        }
    }

    /// Runs the bundled 7zz without putting credentials in its arguments or environment.
    static func run(
        _ arguments: [String],
        password: String?,
        passwordPromptCount: UInt8 = 1,
        directory: URL? = nil,
        controller: ArchiveTaskController? = nil,
        consumeOutput: ((FileHandle) throws -> Void)? = nil
    ) throws -> Result {
        try controller?.checkpoint()
        if let password { try validatePassword(password) }

        let process = Process()
        process.executableURL = try executableURL()
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = password.map { _ in Pipe() }
        process.standardOutput = stdout
        process.standardError = stderr
        if let stdin {
            // A command may exit or may not need the supplied password at all.
            // Suppress SIGPIPE on this descriptor so an early exit cannot kill BoltZip.
            guard fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            process.standardInput = stdin
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        try process.run()
        let child = OSAllocatedUnfairLock<Process?>(initialState: process)
        let stop: @Sendable () -> Void = {
            child.withLock { running in
                if let running, running.isRunning {
                    // SIGKILL also stops a paused child. Archive writes use a temporary output.
                    _ = Darwin.kill(running.processIdentifier, SIGKILL)
                }
            }
        }
        controller?.setHooks(
            onPause: { [weak controller] _ in
                guard let controller else { return }
                child.withLock { running in
                    if let running, running.isRunning {
                        _ = Darwin.kill(running.processIdentifier, controller.isPaused ? SIGSTOP : SIGCONT)
                    }
                }
            },
            onCancel: stop
        )
        defer { controller?.clearHooks() }

        let io = DispatchGroup()
        let capturedError = OSAllocatedUnfairLock<Swift.Result<Data, Error>>(initialState: .success(Data()))
        DispatchQueue.global(qos: .utility).async(group: io) {
            let capture = Swift.Result {
                try captureOutput(stderr.fileHandleForReading, limit: 1024 * 1024).data
            }
            if case .failure = capture { stop() }
            capturedError.withLock { $0 = capture }
        }
        if let stdin, let password {
            DispatchQueue.global(qos: .utility).async(group: io) {
                let writer = stdin.fileHandleForWriting
                defer { try? writer.close() }
                let line = Data((password + "\n").utf8)
                for _ in 0..<passwordPromptCount {
                    do {
                        try writer.write(contentsOf: line)
                    } catch {
                        // The command may close stdin without reading the supplied password.
                        return
                    }
                }
            }
        }

        let capturedOutput = Swift.Result<Data, Error> {
            let reader = stdout.fileHandleForReading
            if let consumeOutput {
                try consumeOutput(reader)
                // A consumer can return after reading a prefix. Drain the rest before waiting.
                _ = try captureOutput(reader, limit: 0)
                return Data()
            }
            let capture = try captureOutput(reader, limit: 64 * 1024 * 1024)
            guard !capture.truncated else { throw CocoaError(.fileReadTooLarge) }
            return capture.data
        }
        if case .failure = capturedOutput { stop() }

        process.waitUntilExit()
        child.withLock { $0 = nil }
        io.wait()
        if controller?.isCancelled == true { throw BoltZipError.cancelled }
        return Result(
            status: process.terminationStatus,
            stdout: try capturedOutput.get(),
            stderr: try capturedError.withLock { try $0.get() }
        )
    }

    private static func captureOutput(_ reader: FileHandle, limit: Int) throws -> (data: Data, truncated: Bool) {
        var data = Data()
        var truncated = false
        while let chunk = try reader.read(upToCount: 64 * 1024), !chunk.isEmpty {
            let remaining = limit - data.count
            if chunk.count > remaining { truncated = true }
            data.append(contentsOf: chunk.prefix(remaining))
        }
        return (data, truncated)
    }

    private static func executableURL() throws -> URL {
        let bundle = Bundle.main.bundleURL
        let executableDirectory = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        let enclosingContents = executableDirectory?.deletingLastPathComponent()
        let contents: URL?
        if bundle.pathExtension == "app" {
            contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        } else if enclosingContents?.lastPathComponent == "Contents",
                  enclosingContents?.deletingLastPathComponent().pathExtension == "app" {
            // A packaged boltzip CLI can be invoked directly from Contents/Helpers.
            contents = enclosingContents
        } else {
            contents = nil
        }

        let helper: URL
        if let contents {
            helper = contents.appendingPathComponent("Helpers/7zz", isDirectory: false)
        } else {
            // Source builds and SwiftPM tests use the checked-in copy, independent of the working directory.
            helper = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Formats
                .deletingLastPathComponent() // BoltZipCore
                .deletingLastPathComponent() // Sources
                .deletingLastPathComponent() // package root
                .appendingPathComponent("Vendor/SevenZip/7zz", isDirectory: false)
        }
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw ArchiveOperationError.sevenZipEngineUnavailable
        }
        return helper
    }
}
