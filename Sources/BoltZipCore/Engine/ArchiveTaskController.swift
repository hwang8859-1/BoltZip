import Foundation

/// Thread-safe cooperative pause and cancellation controller for long-running archive operations.
public final class ArchiveTaskController: @unchecked Sendable {
    private let condition = NSCondition()
    private var _isPaused = false
    private var _isCancelled = false
    private var onPauseHook: (@Sendable (Bool) -> Void)?
    private var onCancelHook: (@Sendable () -> Void)?

    public init() {}

    public var isPaused: Bool {
        condition.lock()
        defer { condition.unlock() }
        return _isPaused
    }

    public var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return _isCancelled
    }

    public func setPaused(_ paused: Bool) {
        condition.lock()
        let changed = (_isPaused != paused)
        _isPaused = paused
        let hook = changed ? onPauseHook : nil
        condition.broadcast()
        condition.unlock()
        hook?(paused)
    }

    public func cancel() {
        condition.lock()
        let wasPaused = _isPaused
        _isCancelled = true
        _isPaused = false
        let pauseHook = wasPaused ? onPauseHook : nil
        let cancelHook = onCancelHook
        condition.broadcast()
        condition.unlock()
        pauseHook?(false)
        cancelHook?()
    }

    public func setHooks(
        onPause: (@Sendable (Bool) -> Void)? = nil,
        onCancel: (@Sendable () -> Void)? = nil
    ) {
        condition.lock()
        onPauseHook = onPause
        onCancelHook = onCancel
        let pausedNow = _isPaused
        let cancelledNow = _isCancelled
        condition.unlock()

        if cancelledNow {
            onCancel?()
        } else if pausedNow {
            onPause?(true)
        }
    }

    public func clearHooks() {
        condition.lock()
        onPauseHook = nil
        onCancelHook = nil
        condition.unlock()
    }

    /// Blocks cleanly via `NSCondition.wait()` while paused and throws `BoltZipError.cancelled` when stopped.
    public func checkpoint() throws {
        condition.lock()
        defer { condition.unlock() }
        while _isPaused && !_isCancelled {
            condition.wait()
        }
        if _isCancelled {
            throw BoltZipError.cancelled
        }
    }
}
