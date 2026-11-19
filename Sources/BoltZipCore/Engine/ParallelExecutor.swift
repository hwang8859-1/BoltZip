import CBoltCompression
import Foundation
import os

/// Thread-safe global concurrency settings for multi-core archive operations and C codec threads.
public enum BoltConcurrency: Sendable {
    public static let userDefaultsKey = "BoltZip.WorkerCoreCount"
    public static let defaultStreamThresholdBytes: UInt64 = 64 * 1024 * 1024
    public static let streamChunkSize: Int = 1024 * 1024

    private static let preferenceLock = OSAllocatedUnfairLock<MultiCorePreference?>(initialState: nil)
    private static let streamThresholdLock = OSAllocatedUnfairLock<UInt64>(initialState: 64 * 1024 * 1024)

    public static var streamingThresholdBytes: UInt64 {
        get { streamThresholdLock.withLock { $0 } }
        set { streamThresholdLock.withLock { $0 = max(4096, newValue) } }
    }

    public static var hardwareCoreCount: Int {
        max(1, Int(bolt_active_cores()))
    }

    public static var autoWorkerCount: Int {
        min(12, max(1, hardwareCoreCount))
    }

    public static var preference: MultiCorePreference {
        get {
            if let cached = preferenceLock.withLock({ $0 }) {
                return cached
            }
            let raw = UserDefaults.standard.integer(forKey: userDefaultsKey)
            let loaded = MultiCorePreference(rawStorageValue: raw)
            preferenceLock.withLock { stored in
                if stored == nil {
                    stored = loaded
                }
            }
            return preferenceLock.withLock({ $0 }) ?? loaded
        }
        set {
            setPreference(newValue, persist: true)
        }
    }

    public static func setPreference(_ newValue: MultiCorePreference, persist: Bool = true) {
        let normalized: MultiCorePreference
        switch newValue {
        case .auto:
            normalized = .auto
        case .fixed(let count):
            normalized = .fixed(max(1, count))
        }
        preferenceLock.withLock { $0 = normalized }
        if persist {
            UserDefaults.standard.set(normalized.rawStorageValue, forKey: userDefaultsKey)
        }
    }

    public static func resolvedWorkerCount(override: Int? = nil) -> Int {
        let hw = hardwareCoreCount
        if let override {
            if override <= 0 {
                return autoWorkerCount
            }
            return min(override, hw)
        }
        switch preference {
        case .auto:
            return autoWorkerCount
        case .fixed(let count):
            return min(max(1, count), hw)
        }
    }
}

private final class OrderedCoordinatorState<Output: Sendable>: @unchecked Sendable {
    let cond = NSCondition()
    var nextToDispatch = 0
    var nextToConsume = 0
    var activeWorkers = 0
    var retainedBytes: UInt64 = 0
    var completed: [Int: Output] = [:]
    var firstError: Error?
}

enum ParallelExecutor {
    static var defaultWorkerCount: Int {
        BoltConcurrency.resolvedWorkerCount()
    }

    static func forEachBounded<T: Sendable>(
        _ items: [T],
        maxWorkers: Int = ParallelExecutor.defaultWorkerCount,
        controller: ArchiveTaskController? = nil,
        body: @escaping @Sendable (Int, T) throws -> Void
    ) throws {
        guard !items.isEmpty else { return }
        if items.count == 1 || maxWorkers <= 1 {
            for (idx, item) in items.enumerated() {
                try controller?.checkpoint()
                try body(idx, item)
            }
            return
        }

        let workers = min(maxWorkers, items.count)
        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()
        let nextIndexLock = OSAllocatedUnfairLock(initialState: 0)
        let errorLock = OSAllocatedUnfairLock<Error?>(initialState: nil)

        for _ in 0..<workers {
            group.enter()
            queue.async {
                defer { group.leave() }
                while true {
                    if let _ = errorLock.withLock({ $0 }) { return }
                    let idx: Int? = nextIndexLock.withLock { cursor in
                        guard cursor < items.count else { return nil }
                        let current = cursor
                        cursor += 1
                        return current
                    }
                    guard let idx else { return }
                    do {
                        try controller?.checkpoint()
                        try body(idx, items[idx])
                    } catch {
                        errorLock.withLock { stored in
                            if stored == nil { stored = error }
                        }
                        return
                    }
                }
            }
        }

        group.wait()
        if let err = errorLock.withLock({ $0 }) {
            throw err
        }
    }

    static func orderedMap<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maxWorkers: Int = ParallelExecutor.defaultWorkerCount,
        maxWindowBytes: UInt64 = 256 * 1024 * 1024,
        byteCost: @escaping @Sendable (Input) -> UInt64,
        controller: ArchiveTaskController? = nil,
        transform: @escaping @Sendable (Int, Input) throws -> Output,
        consumeInOrder: (Int, Input, Output) throws -> Void
    ) throws {
        guard !inputs.isEmpty else { return }
        if inputs.count == 1 || maxWorkers <= 1 {
            for (idx, input) in inputs.enumerated() {
                try controller?.checkpoint()
                let out = try transform(idx, input)
                try consumeInOrder(idx, input, out)
            }
            return
        }

        let workers = min(maxWorkers, inputs.count)
        let maxWindowItems = max(workers * 2, 4)
        let state = OrderedCoordinatorState<Output>()
        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()

        for _ in 0..<workers {
            group.enter()
            queue.async {
                defer { group.leave() }
                while true {
                    state.cond.lock()
                    while state.firstError == nil && state.nextToDispatch < inputs.count {
                        let retainedCount = state.nextToDispatch - state.nextToConsume
                        let nextCost = byteCost(inputs[state.nextToDispatch])
                        let tooManyItems = retainedCount >= maxWindowItems
                        let tooManyBytes = retainedCount > 0 && (state.retainedBytes + nextCost) > maxWindowBytes
                        if !tooManyItems && !tooManyBytes {
                            break
                        }
                        state.cond.wait()
                    }
                    if state.firstError != nil || state.nextToDispatch >= inputs.count {
                        state.cond.unlock()
                        return
                    }
                    let idx = state.nextToDispatch
                    state.nextToDispatch += 1
                    state.retainedBytes += byteCost(inputs[idx])
                    state.activeWorkers += 1
                    state.cond.unlock()

                    do {
                        try controller?.checkpoint()
                        let result = try transform(idx, inputs[idx])
                        state.cond.lock()
                        state.activeWorkers -= 1
                        state.completed[idx] = result
                        state.cond.broadcast()
                        state.cond.unlock()
                    } catch {
                        state.cond.lock()
                        state.activeWorkers -= 1
                        if state.firstError == nil {
                            state.firstError = error
                        }
                        state.cond.broadcast()
                        state.cond.unlock()
                        return
                    }
                }
            }
        }

        var consumerError: Error?
        for consumeIdx in 0..<inputs.count {
            state.cond.lock()
            while state.firstError == nil && state.completed[consumeIdx] == nil {
                state.cond.wait()
            }
            if let workerErr = state.firstError {
                state.cond.unlock()
                consumerError = workerErr
                break
            }
            let output = state.completed.removeValue(forKey: consumeIdx)!
            let cost = byteCost(inputs[consumeIdx])
            state.retainedBytes = state.retainedBytes >= cost ? (state.retainedBytes - cost) : 0
            state.nextToConsume = consumeIdx + 1
            state.cond.broadcast()
            state.cond.unlock()

            do {
                try consumeInOrder(consumeIdx, inputs[consumeIdx], output)
            } catch {
                state.cond.lock()
                if state.firstError == nil {
                    state.firstError = error
                }
                state.cond.broadcast()
                state.cond.unlock()
                consumerError = error
                break
            }
        }

        group.wait()
        if let err = consumerError ?? state.firstError {
            throw err
        }
    }
}
