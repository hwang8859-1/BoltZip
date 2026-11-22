import Foundation

public struct ArchiveConversionItemResult: Sendable {
    public let sourceURL: URL
    public let destinationURLs: [URL]
    public let entryCount: Int
    public let succeeded: Bool
    public let error: (any Error)?

    public init(
        sourceURL: URL,
        destinationURLs: [URL],
        entryCount: Int,
        succeeded: Bool,
        error: (any Error)? = nil
    ) {
        self.sourceURL = sourceURL
        self.destinationURLs = destinationURLs
        self.entryCount = entryCount
        self.succeeded = succeeded
        self.error = error
    }
}

public struct ArchiveConversionReport: Sendable {
    public let results: [ArchiveConversionItemResult]
    public let elapsedSeconds: TimeInterval

    public var succeededCount: Int { results.filter(\.succeeded).count }
    public var failedCount: Int { results.filter { !$0.succeeded }.count }
    public var isAllHealthy: Bool { failedCount == 0 && !results.isEmpty }
}

extension BoltArchiveEngine {
    public static func convertArchives(
        sources: [URL],
        destinationDirectory: URL,
        options: CreateArchiveOptions,
        sourcePassword: String? = nil,
        sourcePasswordProvider: (@Sendable (URL, Bool) throws -> String?)? = nil,
        overwritePolicy: OverwritePolicy = .rename,
        encoding: FilenameEncodingOption = .auto,
        namingTemplate: String = "{name}",
        controller: ArchiveTaskController? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws -> ArchiveConversionReport {
        let start = CFAbsoluteTimeGetCurrent()
        try controller?.checkpoint()

        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: destinationDirectory.path),
           (attrs[.type] as? FileAttributeType) != .typeDirectory {
            throw ArchiveOperationError.outputIsDirectory(destinationDirectory.lastPathComponent)
        }
        try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        var inputProtectedKeys: Set<String> = []
        for src in sources {
            let protected = (try? extractionSourceURLs(archiveURL: src, password: sourcePassword)) ?? [src]
            for url in protected {
                inputProtectedKeys.insert(ArchiveExtractionDestination.pathKey(url))
            }
        }
        var reservedKeys = inputProtectedKeys

        var results: [ArchiveConversionItemResult] = []
        let totalCount = max(1, sources.count)

        for (index, sourceURL) in sources.enumerated() {
            try controller?.checkpoint()
            let baseFraction = Double(index) / Double(totalCount)
            let slice = 1.0 / Double(totalCount)
            progress?(OperationProgress(
                fractionCompleted: baseFraction,
                currentItem: sourceURL.lastPathComponent
            ))

            do {
                let (listing, resolvedPassword) = try inspectWithPasswordRetry(
                    archiveURL: sourceURL,
                    initialPassword: sourcePassword,
                    encoding: encoding,
                    passwordProvider: sourcePasswordProvider
                )
                let sourceProtected = try extractionSourceURLs(archiveURL: sourceURL, password: resolvedPassword)
                for url in sourceProtected {
                    let key = ArchiveExtractionDestination.pathKey(url)
                    inputProtectedKeys.insert(key)
                    reservedKeys.insert(key)
                }

                let stageRoot = try ArchiveExtractionDestination.makeExtractionStage(
                    near: destinationDirectory.appendingPathComponent("convert-\(index)"),
                    under: destinationDirectory
                )
                defer { try? fm.removeItem(at: stageRoot) }

                let extractStage = stageRoot.appendingPathComponent("extracted", isDirectory: true)
                try fm.createDirectory(at: extractStage, withIntermediateDirectories: false)

                var extractOptions = ExtractOptions(
                    destinationURL: extractStage,
                    mode: .here,
                    overwritePolicy: .overwrite,
                    password: resolvedPassword,
                    encoding: encoding,
                    stripMacJunk: options.excludeMacJunk,
                    workerCount: options.workerCount,
                    restoreSymlinks: options.preserveSymlinks
                )
                extractOptions.protectedArchiveURLs = sources

                var activeExtractPassword = resolvedPassword
                var wrongAttempts = 0
                while true {
                    try controller?.checkpoint()
                    var currentOpts = extractOptions
                    currentOpts.password = activeExtractPassword
                    do {
                        try extract(archiveURL: sourceURL, options: currentOpts, controller: controller) { p in
                            progress?(OperationProgress(
                                fractionCompleted: baseFraction + slice * 0.45 * p.fractionCompleted,
                                currentItem: sourceURL.lastPathComponent,
                                processedBytes: p.processedBytes,
                                totalBytes: p.totalBytes
                            ))
                        }
                        break
                    } catch BoltZipError.passwordRequired {
                        guard let provider = sourcePasswordProvider,
                              let supplied = try provider(sourceURL, wrongAttempts > 0) else {
                            throw BoltZipError.passwordRequired(sourceURL.lastPathComponent)
                        }
                        activeExtractPassword = supplied
                    } catch BoltZipError.wrongPassword {
                        wrongAttempts += 1
                        guard let provider = sourcePasswordProvider,
                              let supplied = try provider(sourceURL, true) else {
                            throw BoltZipError.wrongPassword(sourceURL.lastPathComponent)
                        }
                        activeExtractPassword = supplied
                    }
                }

                let rawChildren = try fm.contentsOfDirectory(at: extractStage, includingPropertiesForKeys: nil, options: [])
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }

                let baseStem = archiveBaseStem(sourceURL)
                let renderedStem = CompressionProfile.resolveBaseStem(
                    template: namingTemplate,
                    defaultStem: baseStem,
                    format: options.format
                )

                let targetOutput = CompressionProfile.makeOutputURL(
                    stem: renderedStem,
                    format: options.format,
                    splitVolumeSizeBytes: options.splitVolumeSizeBytes,
                    in: destinationDirectory,
                    deduplicating: overwritePolicy == .rename,
                    reservedPaths: overwritePolicy == .rename ? reservedKeys : []
                )

                let targetKey = ArchiveExtractionDestination.pathKey(targetOutput)
                if overwritePolicy == .skip && fm.fileExists(atPath: targetOutput.path) {
                    results.append(ArchiveConversionItemResult(
                        sourceURL: sourceURL,
                        destinationURLs: [],
                        entryCount: listing.entries.count,
                        succeeded: true,
                        error: nil
                    ))
                    continue
                }
                if overwritePolicy == .overwrite {
                    var candidateTargetKeys: [String] = [targetKey]
                    if options.format == .zip && (options.splitVolumeSizeBytes ?? 0) >= 65536 {
                        let firstVol = targetOutput.deletingPathExtension().appendingPathExtension("z01")
                        candidateTargetKeys.append(ArchiveExtractionDestination.pathKey(firstVol))
                    }
                    if candidateTargetKeys.contains(where: { inputProtectedKeys.contains($0) }) {
                        throw ArchiveOperationError.outputIsInput
                    }
                }

                let createdURLs: [URL]
                if rawChildren.isEmpty && options.format == .sevenZip {
                    // Use streaming libarchive 7z writer so an empty archive produces a valid empty .7z cleanly
                    var emptyOpts = options
                    emptyOpts.encryption = .none
                    emptyOpts.password = nil
                    emptyOpts.splitVolumeSizeBytes = nil
                    try ExtendedArchiveDriver.create7z(
                        from: [],
                        to: targetOutput,
                        algorithm: options.algorithm,
                        level: options.level,
                        excludeMacJunk: options.excludeMacJunk,
                        preserveSymlinks: options.preserveSymlinks,
                        excludePatterns: options.excludePatterns,
                        controller: controller
                    )
                    createdURLs = [targetOutput]
                } else {
                    createdURLs = try createArchive(
                        from: rawChildren,
                        to: targetOutput,
                        options: options,
                        controller: controller
                    ) { p in
                        progress?(OperationProgress(
                            fractionCompleted: baseFraction + slice * (0.45 + 0.55 * p.fractionCompleted),
                            currentItem: targetOutput.lastPathComponent,
                            processedBytes: p.processedBytes,
                            totalBytes: p.totalBytes
                        ))
                    }
                }

                for url in createdURLs {
                    reservedKeys.insert(ArchiveExtractionDestination.pathKey(url))
                }
                results.append(ArchiveConversionItemResult(
                    sourceURL: sourceURL,
                    destinationURLs: createdURLs,
                    entryCount: listing.entries.count,
                    succeeded: true,
                    error: nil
                ))
            } catch BoltZipError.cancelled {
                throw BoltZipError.cancelled
            } catch {
                results.append(ArchiveConversionItemResult(
                    sourceURL: sourceURL,
                    destinationURLs: [],
                    entryCount: 0,
                    succeeded: false,
                    error: error
                ))
            }
        }

        progress?(OperationProgress(fractionCompleted: 1.0, currentItem: destinationDirectory.lastPathComponent))
        return ArchiveConversionReport(
            results: results,
            elapsedSeconds: CFAbsoluteTimeGetCurrent() - start
        )
    }

    private static func inspectWithPasswordRetry(
        archiveURL: URL,
        initialPassword: String?,
        encoding: FilenameEncodingOption,
        passwordProvider: (@Sendable (URL, Bool) throws -> String?)?
    ) throws -> (listing: ArchiveListing, password: String?) {
        var currentPassword = initialPassword
        var wrongAttempt = false
        while true {
            do {
                let listing = try inspect(archiveURL: archiveURL, encoding: encoding, password: currentPassword)
                return (listing, currentPassword)
            } catch BoltZipError.passwordRequired {
                guard let provider = passwordProvider,
                      let next = try provider(archiveURL, false) else {
                    throw BoltZipError.passwordRequired(archiveURL.lastPathComponent)
                }
                currentPassword = next
                wrongAttempt = true
            } catch BoltZipError.wrongPassword {
                guard let provider = passwordProvider,
                      let next = try provider(archiveURL, true || wrongAttempt) else {
                    throw BoltZipError.wrongPassword(archiveURL.lastPathComponent)
                }
                currentPassword = next
                wrongAttempt = true
            }
        }
    }
}
