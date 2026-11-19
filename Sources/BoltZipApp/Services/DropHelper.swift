import Foundation
import UniformTypeIdentifiers

private final class URLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        items.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

enum DropHelper {
    static func extractFileURLs(
        from providers: [NSItemProvider],
        completion: @escaping @MainActor @Sendable ([URL]) -> Void
    ) -> Bool {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !matching.isEmpty else { return false }

        let group = DispatchGroup()
        let accumulator = URLAccumulator()

        for provider in matching {
            group.enter()
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                if let data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.isFileURL {
                    accumulator.append(url.standardizedFileURL)
                }
            }
        }

        group.notify(queue: .main) {
            var seen: Set<String> = []
            let finalURLs = accumulator.snapshot().filter { seen.insert($0.path).inserted }
            Task { @MainActor in
                completion(finalURLs)
            }
        }
        return true
    }

    /// Pure-Swift zero-allocation decimal file size formatter matching `.file` units (`B`, `KB`, `MB`, `GB`, `TB`).
    static func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1_000 {
            return "\(bytes) B"
        }
        let value = Double(bytes)
        if bytes < 1_000_000 {
            let kb = max(1, Int((value / 1_000.0).rounded()))
            return "\(kb) KB"
        }
        if bytes < 1_000_000_000 {
            return String(format: "%.1f MB", value / 1_000_000.0)
        }
        if bytes < 1_000_000_000_000 {
            return String(format: "%.2f GB", value / 1_000_000_000.0)
        }
        return String(format: "%.2f TB", value / 1_000_000_000_000.0)
    }
}
