import BoltZipCore
import SwiftUI

struct QuickTaskHUDView: View {
    let vm: WorkspaceViewModel
    @Bindable var hud: QuickTaskHUDModel
    @FocusState private var passwordFieldFocused: Bool

    private var l10n: L10n { vm.l10n }

    var body: some View {
        BoltGlassContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                progressSection

                if case .needsPassword(_, let wrongAttempt) = hud.phase {
                    passwordPromptSection(wrongAttempt: wrongAttempt)
                }

                footerRow
            }
            .padding(16)
            .frame(width: 404)
            .modifier(HUDSurfaceModifier(useLiquidGlass: vm.supportsLiquidGlass))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onHover { hovering in
            hud.setHovering(hovering)
        }
        .onChange(of: hud.phase) { _, newPhase in
            if case .needsPassword = newPhase {
                passwordFieldFocused = true
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: hud.phase)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            statusIconBadge

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(primaryTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let badge = hud.currentOperation?.formatBadge {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }

                    if !hud.pendingQueue.isEmpty {
                        Text(l10n.hudQueuedBadge(hud.pendingQueue.count))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                }

                Text(hud.currentOperation?.targetName ?? "")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            rightHeaderMetric
        }
    }

    @ViewBuilder
    private var statusIconBadge: some View {
        let spec = badgeSpec
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(spec.tint.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(spec.tint.opacity(0.28), lineWidth: 0.75)
                )

            Image(systemName: spec.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(spec.tint)
                .symbolEffect(.pulse, isActive: isWorkingAndUnpaused)
        }
        .frame(width: 38, height: 38)
    }

    @ViewBuilder
    private var rightHeaderMetric: some View {
        switch hud.phase {
        case .preparing, .running, .paused:
            Text(hud.percentageText)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(hud.phase == .paused ? Color.orange : Color.primary)
                .contentTransition(.numericText())
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19))
                .foregroundStyle(.green)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 19))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.red)
        case .needsPassword:
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 19))
                .foregroundStyle(.indigo)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Progress Bar & Bytes

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HUDProgressTrack(
                fraction: hud.fractionCompleted,
                isIndeterminate: hud.isIndeterminate,
                tint: progressGradientColors,
                isPaused: hud.phase == .paused
            )

            HStack(spacing: 8) {
                Text(subtitleItemText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if let bytesText = hud.bytesStatusText {
                    Text(bytesText)
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Inline Password Prompt

    private func passwordPromptSection(wrongAttempt: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().opacity(0.45)

            if wrongAttempt {
                Text(l10n.hudNeedsPassword)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                SecureField(l10n.passwordPlaceholder, text: $hud.passwordInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($passwordFieldFocused)
                    .onSubmit {
                        hud.submitPassword()
                    }

                Button(l10n.cancel) {
                    hud.cancelPasswordPrompt()
                }
                .controlSize(.small)
                .boltGlassButton()

                Button(l10n.hudUnlockBtn) {
                    hud.submitPassword()
                }
                .controlSize(.small)
                .disabled(hud.passwordInput.isEmpty)
                .boltGlassProminentButton()
            }
        }
    }

    // MARK: - Footer (ETA, Speed, Pause / Resume / Stop)

    private var footerRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                statusDot

                Text(hud.footerStatusText(using: l10n))
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(footerTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let speed = hud.speedText {
                    Text("· \(speed)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            actionButtons
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch hud.phase {
        case .preparing, .running:
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
        case .paused:
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
        case .completed:
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
        case .failed:
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch hud.phase {
        case .preparing, .running, .paused:
            HStack(spacing: 6) {
                Button {
                    hud.togglePause()
                } label: {
                    Label(
                        hud.phase == .paused ? l10n.hudResumeBtn : l10n.hudPauseBtn,
                        systemImage: hud.phase == .paused ? "play.fill" : "pause.fill"
                    )
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .foregroundStyle(hud.phase == .paused ? Color.white : Color.primary)
                .background(
                    Capsule().fill(
                        hud.phase == .paused
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(Color.primary.opacity(0.09))
                    )
                )
                .contentShape(Capsule())

                Button {
                    hud.stop()
                } label: {
                    Label(l10n.hudStopBtn, systemImage: "stop.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.red.opacity(0.92))
                .background(Capsule().fill(Color.red.opacity(0.11)))
                .contentShape(Capsule())
            }

        case .completed:
            HStack(spacing: 6) {
                Button(l10n.hudRevealBtn) {
                    hud.revealResult()
                }
                .controlSize(.small)
                .boltGlassProminentButton()

                Button(l10n.close) {
                    hud.dismiss()
                }
                .controlSize(.small)
                .boltGlassButton()
            }

        case .cancelled, .failed:
            Button(l10n.close) {
                hud.dismiss()
            }
            .controlSize(.small)
            .boltGlassButton()

        case .idle, .needsPassword:
            EmptyView()
        }
    }

    // MARK: - Computed Presentation Helpers

    private var isWorkingAndUnpaused: Bool {
        switch hud.phase {
        case .preparing, .running:
            return true
        default:
            return false
        }
    }

    private var primaryTitle: String {
        switch hud.phase {
        case .paused:
            return l10n.hudPausedTitle
        case .completed:
            return l10n.hudCompletedTitle
        case .cancelled:
            return l10n.hudCancelledTitle
        case .failed:
            return l10n.hudFailedTitle
        case .needsPassword:
            return l10n.hudNeedsPassword
        default:
            return hud.currentOperation?.title(using: l10n) ?? l10n.hudPreparing
        }
    }

    private var subtitleItemText: String {
        switch hud.phase {
        case .failed:
            return hud.currentOperation?.targetName ?? ""
        default:
            return hud.currentItem.isEmpty ? l10n.hudPreparing : hud.currentItem
        }
    }

    private var footerTextColor: Color {
        switch hud.phase {
        case .failed: return .red
        case .paused: return .orange
        default: return .secondary
        }
    }

    private var badgeSpec: (symbol: String, tint: Color) {
        switch hud.phase {
        case .paused:
            return ("pause.fill", .orange)
        case .completed:
            return ("checkmark", .green)
        case .cancelled:
            return ("xmark", .secondary)
        case .failed:
            return ("exclamationmark.triangle.fill", .red)
        case .needsPassword:
            return ("lock.fill", .indigo)
        default:
            if hud.currentOperation?.isCompress == true {
                return ("doc.zipper", .blue)
            }
            return ("shippingbox.and.arrow.backward.fill", .teal)
        }
    }

    private var progressGradientColors: [Color] {
        switch hud.phase {
        case .paused:
            return [.orange.opacity(0.85), .yellow.opacity(0.85)]
        case .completed:
            return [.green, .mint]
        case .failed:
            return [.red, .orange]
        case .cancelled:
            return [.gray.opacity(0.6), .gray.opacity(0.45)]
        default:
            if hud.currentOperation?.isCompress == true {
                return [.indigo, .blue]
            }
            return [.blue, .cyan]
        }
    }
}

private struct HUDSurfaceModifier: ViewModifier {
    let useLiquidGlass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if useLiquidGlass {
            content
                .boltGlassSurface(.regular, in: shape)
                .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(
                    shape
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.20), radius: 14, y: 6)
        }
    }
}

private struct HUDProgressTrack: View {
    let fraction: Double
    let isIndeterminate: Bool
    let tint: [Color]
    let isPaused: Bool

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.09))

                if isIndeterminate && !isPaused {
                    TimelineView(.animation) { context in
                        let cycle = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.35) / 1.35
                        let pillWidth = width * 0.34
                        let travel = width + pillWidth
                        let xOffset = -pillWidth + (travel * cycle)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: tint,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: pillWidth)
                            .offset(x: xOffset)
                    }
                } else {
                    let clamped = min(max(fraction, 0), 1)
                    let barWidth = clamped > 0 ? max(8, width * clamped) : 0
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: tint,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: barWidth)
                        .animation(.linear(duration: 0.14), value: clamped)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 6.5)
    }
}
