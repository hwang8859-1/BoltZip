import BoltZipCore
import SwiftUI

struct MCPHelpSheet: View {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var copiedConfig = false
    @State private var copiedCommand = false

    private var helperPath: String {
        let bundleHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/boltzip").path
        if FileManager.default.fileExists(atPath: bundleHelper) {
            return bundleHelper
        }
        return "/Applications/BoltZip.app/Contents/Helpers/boltzip"
    }

    private var jsonConfig: String {
        """
        {
          "mcpServers": {
            "boltzip": {
              "command": "\(helperPath)",
              "args": ["mcp"]
            }
          }
        }
        """
    }

    private var commandString: String {
        "\"\(helperPath)\" mcp"
    }

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        VStack(spacing: 12) {
            // Header Badge
            HStack(spacing: 12) {
                BoltHeaderIconBadge(symbol: "cpu.fill", tint: .indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.mcpSheetTitle)
                        .font(BoltType.windowTitle)
                    Text(l.mcpSheetSubtitle)
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

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // Section 1: JSON Config for AI Agents
                    BoltGlassSectionCard(
                        l.mcpConfigSectionTitle,
                        icon: "square.and.arrow.down",
                        iconColor: .indigo,
                        glassEnabled: glassEnabled,
                        contentSpacing: 8
                    ) {
                        Text(l.mcpConfigSectionSubtitle)
                            .font(BoltType.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(jsonConfig)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .boltLayeredSurface(
                                    glassEnabled: glassEnabled,
                                    level: .card,
                                    tone: .regular,
                                    in: RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous)
                                )

                            HStack {
                                Spacer()
                                Button {
                                    copyConfig()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: copiedConfig ? "checkmark.circle.fill" : "doc.on.doc")
                                            .foregroundStyle(copiedConfig ? .green : .accentColor)
                                        Text(copiedConfig ? l.mcpCopiedToast : l.mcpCopyConfigBtn)
                                            .font(BoltType.subbodyMedium)
                                    }
                                }
                                .controlSize(.small)
                                .boltGlassButton()
                            }
                        }
                    }

                    // Section 2: Terminal launch command
                    BoltGlassSectionCard(
                        l.mcpCommandSectionTitle,
                        icon: "terminal",
                        iconColor: .cyan,
                        glassEnabled: glassEnabled,
                        contentSpacing: 8
                    ) {
                        HStack(spacing: 8) {
                            Text(commandString)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .boltLayeredSurface(
                                    glassEnabled: glassEnabled,
                                    level: .card,
                                    tone: .regular,
                                    in: RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous)
                                )

                            Button {
                                copyCommand()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedCommand ? "checkmark.circle.fill" : "doc.on.doc")
                                        .foregroundStyle(copiedCommand ? .green : .accentColor)
                                    Text(copiedCommand ? l.mcpCopiedToast : l.mcpCopyCommandBtn)
                                        .font(BoltType.subbodyMedium)
                                }
                            }
                            .controlSize(.small)
                            .boltGlassButton()
                        }
                    }

                    // Section 3: Available Tools
                    BoltGlassSectionCard(
                        l.mcpToolsSectionTitle,
                        icon: "wrench.and.screwdriver",
                        iconColor: .teal,
                        glassEnabled: glassEnabled,
                        contentSpacing: 6
                    ) {
                        VStack(spacing: 6) {
                            toolRow(name: "boltzip_compress", desc: l.mcpToolCompressDesc, icon: "archivebox", glassEnabled: glassEnabled)
                            toolRow(name: "boltzip_extract", desc: l.mcpToolExtractDesc, icon: "doc.zipper", glassEnabled: glassEnabled)
                            toolRow(name: "boltzip_batch_compress", desc: l.mcpToolBatchCompressDesc, icon: "square.stack.3d.up", glassEnabled: glassEnabled)
                            toolRow(name: "boltzip_batch_extract", desc: l.mcpToolBatchExtractDesc, icon: "square.and.arrow.up.on.square", glassEnabled: glassEnabled)
                            toolRow(name: "boltzip_list", desc: l.mcpToolListDesc, icon: "list.bullet.rectangle", glassEnabled: glassEnabled)
                            toolRow(name: "boltzip_test", desc: l.mcpToolTestDesc, icon: "checkmark.shield", glassEnabled: glassEnabled)
                            toolRow(name: "boltzip_recover_zip", desc: l.mcpToolRecoverZipDesc, icon: "bandage", glassEnabled: glassEnabled)
                        }
                    }
                }
            }

            // Footer
            BoltSheetFooterBar(glassEnabled: glassEnabled) {
                Spacer()
                Button(l.close) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .boltGlassProminentButton()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minWidth: 540, maxWidth: 620, minHeight: 480, maxHeight: 620)
    }

    @ViewBuilder
    private func toolRow(name: String, desc: String, icon: String, glassEnabled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(name)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    level: .card,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )

            Text(desc)
                .font(BoltType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func copyConfig() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jsonConfig, forType: .string)
        copiedConfig = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            copiedConfig = false
        }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandString, forType: .string)
        copiedCommand = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            copiedCommand = false
        }
    }
}
