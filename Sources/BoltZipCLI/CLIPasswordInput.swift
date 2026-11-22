import BoltZipCore
import Darwin
import Foundation

enum CLIPasswordInput {
    static var isInteractiveTTY: Bool {
        isatty(STDIN_FILENO) != 0 && isatty(STDERR_FILENO) != 0
    }

    static func resolveInitialPassword(
        arguments: CLIArguments,
        promptForCreationIfNeeded: Bool = false
    ) throws -> String? {
        let plain = arguments.options["password"]
        let fromStdin = arguments.flags.contains("password-stdin")
        if plain != nil && fromStdin {
            throw BoltZipError.ioError("Cannot combine --password with --password-stdin.")
        }
        if fromStdin {
            return try readPasswordFromStdin()
        }
        if let plain {
            return plain
        }
        if promptForCreationIfNeeded && arguments.flags.contains("ask-password") {
            guard let entered = promptTTY(message: "Enter password: ", verifyTwice: true) else {
                throw BoltZipError.cancelled
            }
            return entered
        }
        return nil
    }

    static func withPasswordRetry<T>(
        archiveURL: URL,
        initialPassword: String?,
        allowTTYPrompt: Bool,
        _ work: (String?) throws -> T
    ) throws -> T {
        var current = initialPassword
        while true {
            do {
                return try work(current)
            } catch BoltZipError.passwordRequired {
                guard allowTTYPrompt,
                      let next = promptTTY(message: "Enter password for \(archiveURL.lastPathComponent): ") else {
                    throw BoltZipError.passwordRequired(archiveURL.lastPathComponent)
                }
                current = next
            } catch BoltZipError.wrongPassword {
                guard allowTTYPrompt,
                      let next = promptTTY(message: "Incorrect password for \(archiveURL.lastPathComponent). Retry: ") else {
                    throw BoltZipError.wrongPassword(archiveURL.lastPathComponent)
                }
                current = next
            }
        }
    }

    static func readPasswordFromStdin() throws -> String {
        guard let line = readLine(strippingNewline: true) else {
            throw BoltZipError.passwordRequired("stdin")
        }
        let cleaned = line.hasSuffix("\r") ? String(line.dropLast()) : line
        guard !cleaned.isEmpty else {
            throw BoltZipError.passwordRequired("stdin")
        }
        return cleaned
    }

    static func promptTTY(message: String, verifyTwice: Bool = false) -> String? {
        guard let first = readHiddenLineFromTTY(prompt: message), !first.isEmpty else {
            return nil
        }
        if !verifyTwice {
            return first
        }
        guard let second = readHiddenLineFromTTY(prompt: "Confirm password: "), second == first else {
            fputs("Passwords did not match.\n", stderr)
            return nil
        }
        return first
    }

    private static func readHiddenLineFromTTY(prompt: String) -> String? {
        let fd = open("/dev/tty", O_RDWR)
        let handleFD: Int32
        let shouldClose: Bool
        if fd >= 0 {
            handleFD = fd
            shouldClose = true
        } else if isatty(STDIN_FILENO) != 0 {
            handleFD = STDIN_FILENO
            shouldClose = false
        } else {
            return nil
        }
        defer {
            if shouldClose { close(handleFD) }
        }

        var oldState = termios()
        let hasTermios = (tcgetattr(handleFD, &oldState) == 0)
        if hasTermios {
            var hidden = oldState
            hidden.c_lflag &= ~UInt(ECHO)
            tcsetattr(handleFD, TCSAFLUSH, &hidden)
        }
        defer {
            if hasTermios {
                tcsetattr(handleFD, TCSAFLUSH, &oldState)
            }
            fputs("\n", stderr)
        }

        fputs(prompt, stderr)
        fflush(stderr)

        var bytes: [UInt8] = []
        var ch: UInt8 = 0
        while Darwin.read(handleFD, &ch, 1) == 1 {
            if ch == 10 || ch == 13 {
                break
            }
            bytes.append(ch)
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}
