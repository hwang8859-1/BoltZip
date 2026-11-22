import AppKit
import BoltZipCore
import SwiftUI

struct EntryPropertiesSheet: View {
    @Bindable var vm: WorkspaceViewModel
    let entry: ArchiveEntry
    @Environment(\.dismiss) private var dismiss

    private static let formatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        return df
    }()

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                BoltHeaderIconBadge(
                    symbol: entry.isDirectory ? "folder.fill" : "doc.text.magnifyingglass",
                    tint: .cyan
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(BoltType.windowTitle)
                    Text(entry.path)
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, BoltMetrics.cardHeaderHPad)
            .padding(.vertical, BoltMetrics.cardHeaderVPad)
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                level: .elevated,
                tone: .regular,
                in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
            )

            VStack(spacing: 8) {
                PropRow(title: l.colOriginalSize, value: entry.isDirectory ? "—" : "\(DropHelper.formatBytes(entry.uncompressedSize)) (\(entry.uncompressedSize) B)")
                PropRow(title: l.colPackedSize, value: entry.isDirectory ? "—" : "\(DropHelper.formatBytes(entry.compressedSize)) (\(entry.compressedSize) B)")
                PropRow(title: l.colRatio, value: entry.isDirectory ? "—" : String(format: "%.2f%%", entry.compressionRatioPercent))
                PropRow(title: l.colMethod, value: entry.compressionMethodName)
                PropRow(title: l.encryptedBadge, value: entry.isEncrypted ? entry.encryptionLabel : "—")
                PropRow(title: "CRC32", value: entry.crc32 == 0 ? "0x00000000" : String(format: "0x%08X", entry.crc32))
                PropRow(title: "POSIX", value: String(format: "0o%03o", entry.permissions))
                PropRow(title: l.colModified, value: Self.formatter.string(from: entry.modifiedDate))
            }
            .padding(14)
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                tone: .regular,
                in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
            )

            Spacer(minLength: 0)

            BoltSheetFooterBar(glassEnabled: glassEnabled) {
                Spacer()
                Button(l.close) { dismiss() }
                    .boltGlassProminentButton()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 450, height: 388)
        .boltUnifiedSheetStyle(vm: vm)
    }
}

private struct PropRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(BoltType.subbody)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Text(value)
                .font(BoltType.monoCaption)
                .textSelection(.enabled)
        }
    }
}

struct IntegrityReportSheet: View {
    @Bindable var vm: WorkspaceViewModel
    let report: IntegrityReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                BoltHeaderIconBadge(
                    symbol: report.isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    tint: report.isHealthy ? .green : .red
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(l.verify) · \(report.archiveName)")
                        .font(BoltType.windowTitle)
                    Text("\(report.passedCount)/\(report.totalEntries) · \(String(format: "%.2fs", report.elapsedSeconds))")
                        .font(BoltType.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, BoltMetrics.cardHeaderHPad)
            .padding(.vertical, BoltMetrics.cardHeaderVPad)
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                level: .elevated,
                tone: .regular,
                in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
            )

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 4) {
                    ForEach(report.results) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.status == .passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(item.status == .passed ? .green : (item.status == .missingPassword ? .orange : .red))
                            Text(item.path)
                                .font(BoltType.subbody)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(item.detail)
                                .font(BoltType.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous))
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous))
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                tone: .regular,
                in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
            )

            BoltSheetFooterBar(glassEnabled: glassEnabled) {
                if !report.isHealthy,
                   let activeListing = vm.listing,
                   activeListing.format == .zip,
                   activeListing.archiveURL.lastPathComponent == report.archiveName {
                    Button(l.recoverZipOfferBtn) {
                        dismiss()
                        vm.activeSheet = .recoverZip(initialSource: activeListing.archiveURL)
                    }
                    .boltGlassButton()
                }
                Spacer()
                Button(l.close) { dismiss() }
                    .boltGlassProminentButton()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 470, height: 365)
        .boltUnifiedSheetStyle(vm: vm)
    }
}

struct BenchmarkSheet: View {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var results: [BenchmarkEntryResult] = []
    @State private var isRunning = false
    @State private var errorMsg: String?
    @State private var hoveredIndex: Int?

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency
        let maxDecompress = results.map(\.decompressMBps).max() ?? 0

        VStack(spacing: 12) {
            BoltGlassContainer(spacing: 8) {
                HStack(spacing: 12) {
                    BoltHeaderIconBadge(symbol: "gauge.with.dots.needle.67percent", tint: .cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.benchmarkTitle)
                            .font(BoltType.windowTitle)
                        Text(l.benchmarkSub)
                            .font(BoltType.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isRunning ? "..." : l.rerunBench) {
                        runBench()
                    }
                    .boltGlassButton()
                    .disabled(isRunning)
                }
                .padding(.horizontal, BoltMetrics.cardHeaderHPad)
                .padding(.vertical, BoltMetrics.cardHeaderVPad)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    level: .elevated,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
                )
            }

                Group {
                    if isRunning {
                        ProgressView(l.runningBench)
                            .font(BoltType.subbody)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMsg {
                        Text(errorMsg)
                            .font(BoltType.subbody)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 4) {
                                ForEach(Array(results.enumerated()), id: \.offset) { idx, r in
                                    let isFastest = maxDecompress > 0 && r.decompressMBps >= maxDecompress - 0.01
                                    HStack(spacing: 8) {
                                        HStack(spacing: 5) {
                                            Text(r.algorithm.shortName)
                                                .font(BoltType.bodyMedium)
                                            Text("lvl \(r.level)")
                                                .font(BoltType.badge)
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.primary.opacity(0.07), in: Capsule())
                                        }
                                        .frame(width: 126, alignment: .leading)

                                        Text(DropHelper.formatBytes(UInt64(r.compressedBytes)))
                                            .font(BoltType.subbody)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                            .frame(width: 72, alignment: .trailing)

                                        HStack(spacing: 5) {
                                            GeometryReader { barGeo in
                                                let pct = min(max(r.ratioPercent / 100.0, 0), 1)
                                                ZStack(alignment: .leading) {
                                                    Capsule()
                                                        .fill(Color.primary.opacity(0.08))
                                                    Capsule()
                                                        .fill(
                                                            LinearGradient(
                                                                colors: [.green, .mint],
                                                                startPoint: .leading,
                                                                endPoint: .trailing
                                                            )
                                                        )
                                                        .frame(width: max(4, barGeo.size.width * pct))
                                                }
                                            }
                                            .frame(width: 34, height: 5)

                                            Text(String(format: "%.1f%%", r.ratioPercent))
                                                .font(BoltType.subbodyMedium)
                                                .monospacedDigit()
                                                .foregroundStyle(.green)
                                        }
                                        .frame(width: 98, alignment: .trailing)

                                        Text(String(format: "%.1f MB/s", r.compressMBps))
                                            .font(BoltType.subbody)
                                            .monospacedDigit()
                                            .frame(width: 84, alignment: .trailing)

                                        Text(String(format: "%.1f MB/s", r.decompressMBps))
                                            .font(isFastest ? BoltType.subbodyMedium : BoltType.subbody)
                                            .monospacedDigit()
                                            .foregroundStyle(isFastest ? Color.cyan : Color.primary)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous)
                                            .fill(
                                                hoveredIndex == idx
                                                    ? Color.primary.opacity(0.08)
                                                    : (idx.isMultiple(of: 2) ? Color.primary.opacity(0.03) : Color.clear)
                                            )
                                    )
                                    .onHover { inside in
                                        hoveredIndex = inside ? idx : (hoveredIndex == idx ? nil : hoveredIndex)
                                    }
                                }
                            }
                            .padding(8)
                        }
                        .boltTopScrollHeaderBar(glassEnabled: glassEnabled, dividerEdge: .bottom) {
                            HStack(spacing: 8) {
                                Text(l.colMethod).frame(width: 126, alignment: .leading)
                                Text(l.colPackedSize).frame(width: 72, alignment: .trailing)
                                Text(l.colRatio).frame(width: 98, alignment: .trailing)
                                Text(l.compressSpeedCol).frame(width: 84, alignment: .trailing)
                                Text(l.decompressSpeedCol).frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .font(BoltType.cardEyebrow)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: BoltMetrics.headerHeight)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous))
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
                )

            BoltSheetFooterBar(glassEnabled: glassEnabled) {
                Image(systemName: "cpu")
                    .font(BoltType.caption)
                    .foregroundStyle(.secondary)
                Text("\(l.benchHardwareNote) · \(vm.multiCoreStatusSummary(l))")
                    .font(BoltType.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(l.done) { dismiss() }
                    .boltGlassProminentButton()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 540, height: 356)
        .boltUnifiedSheetStyle(vm: vm)
        .onAppear {
            if results.isEmpty { runBench() }
        }
    }

    private func runBench() {
        isRunning = true
        errorMsg = nil
        Task.detached(priority: .userInitiated) {
            do {
                let res = try BenchmarkRunner.run()
                await MainActor.run {
                    self.results = res
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self.errorMsg = error.localizedDescription
                    self.isRunning = false
                }
            }
        }
    }
}
