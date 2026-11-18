import Foundation
import os

/// Minimal macOS 10.12+ unfair lock wrapper replacing macOS 13's `OSAllocatedUnfairLock`.
public final class BoltLockedBox<State>: @unchecked Sendable {
    private let lockPtr: os_unfair_lock_t
    private var state: State

    public init(initialState: State) {
        self.lockPtr = .allocate(capacity: 1)
        self.lockPtr.initialize(to: os_unfair_lock())
        self.state = initialState
    }

    deinit {
        lockPtr.deinitialize(count: 1)
        lockPtr.deallocate()
    }

    public func withLock<T>(_ body: (inout State) throws -> T) rethrows -> T {
        os_unfair_lock_lock(lockPtr)
        defer { os_unfair_lock_unlock(lockPtr) }
        return try body(&state)
    }
}
