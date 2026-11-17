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
                if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    accumulator.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            let finalURLs = accumulator.snapshot()
            Task { @MainActor in
                completion(finalURLs)
            }
        }
        return true
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
