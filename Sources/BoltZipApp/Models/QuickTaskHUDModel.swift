import AppKit
import BoltZipCore
import Foundation
import Observation
import os

private final class WeakHUDRef: @unchecked Sendable {
    weak var model: QuickTaskHUDModel?
    init(_ model: QuickTaskHUDModel) {
        self.model = model
    }
}

/// Throttles high-frequency background `OperationProgress` updates before hopping to `@MainActor`.
private final class ProgressThrottleGate: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: TimeInterval(0))
    private let minInterval: TimeInterval

    init(minInterval: TimeInterval = 1.0 / 20.0) {
        self.minInterval = minInterval
    }

    func shouldEmit(fraction: Double) -> Bool {
        if fraction >= 1.0 { return true }
        let now = ProcessInfo.processInfo.systemUptime
        return lock.withLock { lastEmit in
            if now - lastEmit >= minInterval {
                lastEmit = now
                return true
            }
            return false
        }
    }
}

@Observable
@MainActor
final class QuickTaskHUDModel {
    enum Phase: Equatable {
        case idle
        case preparing
        case running
        case paused
        case needsPassword(archiveURL: URL, wrongAttempt: Bool)
        case completed(resultURL: URL, elapsedSeconds: Double)
        case cancelled
        case failed(String)

        var isActiveWork: Bool {
            switch self {
            case .preparing, .running, .paused, .needsPassword:
                return true
            case .idle, .completed, .cancelled, .failed:
                return false
            }
        }
    }

    enum Operation: Sendable, Identifiable {
        case compress(id: UUID = UUID(), inputs: [URL], outputURL: URL, options: CreateArchiveOptions)
        case extract(id: UUID = UUID(), archiveURL: URL, options: ExtractOptions)

        var id: UUID {
            switch self {
            case .compress(let id, _, _, _): return id
            case .extract(let id, _, _): return id
            }
        }

        var isCompress: Bool {
            if case .compress = self { return true }
            return false
        }

        var formatBadge: String {
            switch self {
            case .compress(_, _, _, let options):
                return options.format.fileExtension.uppercased()
            case .extract(_, let archiveURL, _):
                if let detected = ArchiveFormat.detect(from: archiveURL) {
                    return detected.fileExtension.uppercased()
                }
                let ext = archiveURL.pathExtension.uppercased()
                return ext.isEmpty ? "ARCHIVE" : ext
            }
        }

        var targetName: String {
            switch self {
            case .compress(_, _, let outputURL, _):
                return outputURL.lastPathComponent
            case .extract(_, let archiveURL, _):
                return archiveURL.lastPathComponent
            }
        }

        func title(using l10n: L10n) -> String {
            switch self {
            case .compress(_, _, _, let options):
                return l10n.hudCompressingTitle(options.format.fileExtension.uppercased())
            case .extract(_, _, let options):
                switch options.mode {
                case .subfolder:
                    return l10n.hudExtractingSubfolderTitle
                case .smart, .here, .selected:
                    return l10n.hudSmartExtractingTitle
                }
            }
        }

        func withPassword(_ password: String) -> Operation {
            switch self {
            case .compress:
                return self
            case .extract(let id, let archiveURL, let options):
                let updated = ExtractOptions(
                    destinationURL: options.destinationURL,
                    mode: options.mode,
                    overwritePolicy: options.overwritePolicy,
                    password: password,
                    encoding: options.encoding,
                    stripMacJunk: options.stripMacJunk
                )
                return .extract(id: id, archiveURL: archiveURL, options: updated)
            }
        }
    }

    // MARK: - Observable UI State

    private(set) var currentOperation: Operation?
    private(set) var pendingQueue: [Operation] = []
    private(set) var phase: Phase = .idle

    private(set) var fractionCompleted: Double = 0
    private(set) var currentItem: String = ""
    private(set) var processedBytes: UInt64 = 0
    private(set) var totalBytes: UInt64 = 0
    private(set) var smoothedBytesPerSec: Double = 0
    private(set) var activeElapsedSeconds: Double = 0
    private(set) var estimatedRemainingSeconds: Double?

    var passwordInput: String = ""
    private(set) var isHovering: Bool = false

    // MARK: - Window Coordination & Completion Hooks

    var onPresentRequested: (() -> Void)?
    var onDismissRequested: (() -> Void)?
    var onKeyFocusRequested: (() -> Void)?
    var onOperationSucceeded: ((Operation, URL) -> Void)?
    var completionAutoDismissDelay: TimeInterval = 2.6
    var cancelledAutoDismissDelay: TimeInterval = 1.2

    // MARK: - Execution & Timing Internals

    private var activeController: ArchiveTaskController?
    private var runningTask: Task<Void, Never>?
    private var uiTimerTask: Task<Void, Never>?
    private var autoDismissTask: Task<Void, Never>?
    private var activeGeneration: Int = 0

    private var accumulatedActiveSeconds: Double = 0
    private var segmentStartDate: Date?
    private var lastSpeedSampleDate: Date?
    private var lastSpeedSampleBytes: UInt64 = 0

    // MARK: - Computed Helpers

    var isIndeterminate: Bool {
        if case .preparing = phase { return true }
        if case .running = phase, totalBytes == 0 && fractionCompleted < 0.02 { return true }
        return false
    }

    var percentageText: String {
        let clamped = min(max(fractionCompleted, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    var bytesStatusText: String? {
        if totalBytes > 0 {
            return "\(DropHelper.formatBytes(processedBytes)) / \(DropHelper.formatBytes(totalBytes))"
        }
        if processedBytes > 0 {
            return DropHelper.formatBytes(processedBytes)
        }
        return nil
    }

    var speedText: String? {
        guard case .running = phase, smoothedBytesPerSec >= 1024 else { return nil }
        return "\(DropHelper.formatBytes(UInt64(smoothedBytesPerSec)))/s"
    }

    func footerStatusText(using l10n: L10n) -> String {
        switch phase {
        case .idle, .preparing:
            return l10n.hudCalculatingETA
        case .running:
            if let eta = estimatedRemainingSeconds {
                if eta < 1.5 || fractionCompleted >= 0.995 {
                    return l10n.hudAlmostDone
                }
                return l10n.hudRemaining(Self.formatDuration(eta))
            }
            return l10n.hudCalculatingETA
        case .paused:
            return l10n.hudPausedTitle
        case .needsPassword:
            return l10n.hudNeedsPassword
        case .completed(_, let elapsed):
            return l10n.hudElapsed(String(format: "%.1fs", max(0.1, elapsed)))
        case .cancelled:
            return l10n.hudCancelledTitle
        case .failed(let msg):
            return msg
        }
    }

    // MARK: - Queue & Lifecycle

    func enqueue(_ operation: Operation) {
        autoDismissTask?.cancel()
        autoDismissTask = nil

        if phase.isActiveWork {
            pendingQueue.append(operation)
            onPresentRequested?()
            return
        }

        start(operation)
    }

    func togglePause() {
        guard let controller = activeController else { return }
        switch phase {
        case .preparing, .running:
            controller.setPaused(true)
            freezeActiveClock()
            phase = .paused
        case .paused:
            resumeActiveClock()
            phase = .running
            controller.setPaused(false)
        default:
            break
        }
    }

    func stop() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        pendingQueue.removeAll()
        activeController?.cancel()
        activeGeneration &+= 1
        runningTask?.cancel()
        runningTask = nil
        stopUITimer()
        freezeActiveClock()
        phase = .cancelled
        scheduleAutoDismiss(after: cancelledAutoDismissDelay)
    }

    func submitPassword() {
        guard case .needsPassword = phase, let op = currentOperation else { return }
        let entered = passwordInput
        guard !entered.isEmpty else { return }
        passwordInput = ""
        start(op.withPassword(entered), preserveElapsed: false)
    }

    func cancelPasswordPrompt() {
        passwordInput = ""
        stop()
    }

    func revealResult() {
        guard case .completed(let url, _) = phase else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func dismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        if phase.isActiveWork {
            stop()
        }
        stopUITimer()
        phase = .idle
        currentOperation = nil
        pendingQueue.removeAll()
        onDismissRequested?()
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            autoDismissTask?.cancel()
            autoDismissTask = nil
        } else {
            switch phase {
            case .completed:
                scheduleAutoDismiss(after: min(1.2, completionAutoDismissDelay))
            case .cancelled:
                scheduleAutoDismiss(after: min(0.9, cancelledAutoDismissDelay))
            default:
                break
            }
        }
    }

    // MARK: - Private Execution

    private func start(_ operation: Operation, preserveElapsed: Bool = false) {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        runningTask?.cancel()
        stopUITimer()

        activeGeneration &+= 1
        let generation = activeGeneration

        currentOperation = operation
        phase = .preparing
        fractionCompleted = 0
        currentItem = ""
        processedBytes = 0
        totalBytes = 0
        smoothedBytesPerSec = 0
        estimatedRemainingSeconds = nil
        passwordInput = ""
        lastSpeedSampleDate = nil
        lastSpeedSampleBytes = 0

        if !preserveElapsed {
            accumulatedActiveSeconds = 0
            activeElapsedSeconds = 0
        }
        segmentStartDate = Date()

        let controller = ArchiveTaskController()
        activeController = controller
        startUITimer(generation: generation)
        onPresentRequested?()

        let gate = ProgressThrottleGate()
        let ref = WeakHUDRef(self)
        let emitProgress: @Sendable (OperationProgress) -> Void = { progress in
            if gate.shouldEmit(fraction: progress.fractionCompleted) {
                Task { @MainActor in
                    ref.model?.handleProgress(progress, generation: generation)
                }
            }
        }

        runningTask = Task { @MainActor [weak self] in
            do {
                let resultURL = try await Self.executeInBackground(
                    operation: operation,
                    controller: controller,
                    progress: emitProgress
                )
                self?.handleCompletion(resultURL: resultURL, generation: generation)
            } catch {
                self?.handleError(error, operation: operation, generation: generation)
            }
        }
    }

    nonisolated private static func executeInBackground(
        operation: Operation,
        controller: ArchiveTaskController,
        progress: @escaping @Sendable (OperationProgress) -> Void
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            switch operation {
            case .compress(_, let inputs, let outputURL, let options):
                let urls = try BoltArchiveEngine.createArchive(
                    from: inputs,
                    to: outputURL,
                    options: options,
                    controller: controller,
                    progress: progress
                )
                return urls.last ?? outputURL

            case .extract(_, let archiveURL, let options):
                return try BoltArchiveEngine.extract(
                    archiveURL: archiveURL,
                    options: options,
                    controller: controller,
                    progress: progress
                )
            }
        }.value
    }

    private func handleProgress(_ progress: OperationProgress, generation: Int) {
        guard generation == activeGeneration else { return }

        if case .preparing = phase {
            phase = .running
        }

        if progress.fractionCompleted > fractionCompleted || progress.fractionCompleted >= 1.0 {
            fractionCompleted = min(max(progress.fractionCompleted, 0), 1)
        }
        if !progress.currentItem.isEmpty {
            currentItem = progress.currentItem
        }
        if progress.totalBytes > 0 {
            totalBytes = max(totalBytes, progress.totalBytes)
        }
        if progress.processedBytes > processedBytes {
            processedBytes = progress.processedBytes
        }

        updateActiveElapsed()

        // Sample throughput only while running (never across pauses)
        if case .running = phase {
            let now = Date()
            if let lastDate = lastSpeedSampleDate {
                let dt = now.timeIntervalSince(lastDate)
                if dt >= 0.35 && processedBytes >= lastSpeedSampleBytes {
                    let dBytes = Double(processedBytes - lastSpeedSampleBytes)
                    if dBytes > 0 {
                        let inst = dBytes / dt
                        smoothedBytesPerSec = smoothedBytesPerSec == 0
                            ? inst
                            : (smoothedBytesPerSec * 0.72 + inst * 0.28)
                    }
                    lastSpeedSampleDate = now
                    lastSpeedSampleBytes = processedBytes
                }
            } else {
                lastSpeedSampleDate = now
                lastSpeedSampleBytes = processedBytes
            }
            recomputeETA()
        }
    }

    private func handleCompletion(resultURL: URL, generation: Int) {
        guard generation == activeGeneration else { return }
        stopUITimer()
        freezeActiveClock()
        activeController = nil
        runningTask = nil

        fractionCompleted = 1.0
        estimatedRemainingSeconds = 0
        if totalBytes > 0 {
            processedBytes = max(processedBytes, totalBytes)
        }

        if let completedOp = currentOperation {
            onOperationSucceeded?(completedOp, resultURL)
        }

        if !pendingQueue.isEmpty {
            let next = pendingQueue.removeFirst()
            start(next)
            return
        }

        phase = .completed(resultURL: resultURL, elapsedSeconds: activeElapsedSeconds)
        scheduleAutoDismiss(after: completionAutoDismissDelay)
    }

    private func handleError(_ error: Error, operation: Operation, generation: Int) {
        guard generation == activeGeneration else { return }
        stopUITimer()
        freezeActiveClock()
        activeController = nil
        runningTask = nil

        if let boltErr = error as? BoltZipError {
            switch boltErr {
            case .cancelled:
                pendingQueue.removeAll()
                phase = .cancelled
                scheduleAutoDismiss(after: cancelledAutoDismissDelay)
                return
            case .passwordRequired:
                if case .extract(_, let archiveURL, _) = operation {
                    phase = .needsPassword(archiveURL: archiveURL, wrongAttempt: false)
                    onKeyFocusRequested?()
                    return
                }
            case .wrongPassword:
                if case .extract(_, let archiveURL, _) = operation {
                    phase = .needsPassword(archiveURL: archiveURL, wrongAttempt: true)
                    onKeyFocusRequested?()
                    return
                }
            default:
                break
            }
        }

        if !pendingQueue.isEmpty {
            pendingQueue.removeAll()
        }
        phase = .failed(error.localizedDescription)
    }

    // MARK: - Clocks & Timers

    private func startUITimer(generation: Int) {
        uiTimerTask?.cancel()
        uiTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled, self.activeGeneration == generation else { return }
                if case .running = self.phase {
                    self.updateActiveElapsed()
                    self.recomputeETA()
                } else if case .preparing = self.phase {
                    self.updateActiveElapsed()
                }
            }
        }
    }

    private func stopUITimer() {
        uiTimerTask?.cancel()
        uiTimerTask = nil
    }

    private func updateActiveElapsed() {
        if let start = segmentStartDate {
            activeElapsedSeconds = accumulatedActiveSeconds + Date().timeIntervalSince(start)
        } else {
            activeElapsedSeconds = accumulatedActiveSeconds
        }
    }

    private func freezeActiveClock() {
        if let start = segmentStartDate {
            accumulatedActiveSeconds += Date().timeIntervalSince(start)
            segmentStartDate = nil
        }
        activeElapsedSeconds = accumulatedActiveSeconds
        lastSpeedSampleDate = nil
    }

    private func resumeActiveClock() {
        segmentStartDate = Date()
        lastSpeedSampleDate = Date()
        lastSpeedSampleBytes = processedBytes
    }

    private func recomputeETA() {
        guard activeElapsedSeconds >= 0.6 else {
            estimatedRemainingSeconds = nil
            return
        }

        if totalBytes > processedBytes, smoothedBytesPerSec >= 1024 {
            let remaining = Double(totalBytes - processedBytes) / smoothedBytesPerSec
            updateSmoothedETA(remaining)
            return
        }

        if totalBytes == 0, fractionCompleted >= 0.03, fractionCompleted < 0.999 {
            let remaining = activeElapsedSeconds * (1.0 - fractionCompleted) / fractionCompleted
            updateSmoothedETA(remaining)
        }
    }

    private func updateSmoothedETA(_ rawETA: Double) {
        let clamped = min(max(rawETA, 0), 86400)
        if let previous = estimatedRemainingSeconds {
            estimatedRemainingSeconds = previous * 0.65 + clamped * 0.35
        } else {
            estimatedRemainingSeconds = clamped
        }
    }

    private func scheduleAutoDismiss(after seconds: TimeInterval) {
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            guard let self, !Task.isCancelled else { return }
            guard !self.isHovering else { return }
            switch self.phase {
            case .completed, .cancelled:
                self.dismiss()
            default:
                break
            }
        }
    }

    // MARK: - Formatting

    static func formatDuration(_ seconds: Double) -> String {
        let total = max(1, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func computeQuickCompressDestination(inputs: [URL], format: ArchiveFormat) -> URL {
        let parentDir = inputs.first!.deletingLastPathComponent()
        let baseName: String
        if inputs.count == 1, let first = inputs.first {
            let isDir = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            baseName = isDir ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent
        } else {
            let suffix = BoltCoreLocalization.t("归档", "封存檔", "Archive", "アーカイブ")
            baseName = "\(parentDir.lastPathComponent)_\(suffix)"
        }
        let ext = format.fileExtension
        var candidate = parentDir.appendingPathComponent("\(baseName).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parentDir.appendingPathComponent("\(baseName) (\(index)).\(ext)")
            index += 1
        }
        return candidate
    }
}
