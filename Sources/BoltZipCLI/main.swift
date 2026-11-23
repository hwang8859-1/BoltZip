import BoltZipCore
import Darwin

typealias CLIProgress = @Sendable (OperationProgress) -> Void

func runCLI(_ args: [String]) async -> Int32 {
    guard let command = args.first else {
        printUsage()
        return 0
    }

    let arguments = CLIArguments(Array(args.dropFirst()))
    let progress = makeTTYProgressHandler(enabled: !arguments.useJSON && !arguments.flags.contains("quiet"))

    do {
        switch command {
        case "version", "--version", "-v":
            print("BoltZip \(BoltZipVersion.current)")
            return 0
        case "mcp", "--mcp":
            return await MCPServer.run()
        case "associate":
            return await runAssociateCommand(flags: arguments.flags)
        case "engines":
            return ReportCommands.engines()
        case "bench":
            return try ReportCommands.benchmark(arguments)
        case "l":
            return try ReportCommands.list(arguments)
        case "t":
            return try ReportCommands.test(arguments, progress: progress)
        case "x":
            return try ArchiveCommands.extract(arguments, progress: progress)
        case "e":
            return try ArchiveCommands.extractFlat(arguments, progress: progress)
        case "a":
            return try ArchiveCommands.create(arguments, progress: progress)
        case "add":
            return try ArchiveCommands.add(arguments, progress: progress)
        case "rm":
            return try ArchiveCommands.remove(arguments, progress: progress)
        case "mkdir":
            return try ArchiveCommands.makeDirectory(arguments, progress: progress)
        case "mv":
            return try ArchiveCommands.move(arguments, progress: progress)
        case "recover":
            return try ArchiveCommands.recover(arguments, progress: progress)
        default:
            printUsage()
            return 1
        }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

exit(await runCLI(Array(CommandLine.arguments.dropFirst())))
