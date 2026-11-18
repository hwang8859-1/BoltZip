import AppKit
import FinderSync
import Foundation

@objc(FinderSync)
final class FinderSync: FIFinderSync {
    private static let archiveExtensions: Set<String> = [
        "zip", "zipx", "z01", "rar", "r00", "r01", "7z", "tar", "gz", "tgz",
        "zst", "zstd", "tzst", "xz", "txz", "lzma", "bz2", "tbz2", "tbz",
        "lz4", "tlz4", "iso", "cab", "xar", "pkg"
    ]

    override init() {
        super.init()
        // Monitor root filesystem so "Bolt >" top-level menu appears anywhere in Finder
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer, .toolbarItemMenu:
            break
        default:
            return nil
        }

        let targets = currentTargetURLs()
        let hasArchives = targets.contains { isArchiveURL($0) }
        let onlyArchives = !targets.isEmpty && targets.allSatisfy { isArchiveURL($0) }

        let rootMenu = NSMenu(title: "")
        let boltItem = NSMenuItem(title: "Bolt", action: nil, keyEquivalent: "")
        boltItem.image = makeBoltCircleMenuImage()

        let submenu = NSMenu(title: "Bolt")

        if menuKind == .contextualMenuForContainer && (FIFinderSyncController.default().selectedItemURLs()?.isEmpty ?? true) {
            if !targets.isEmpty {
                addItem(to: submenu, title: "将当前文件夹压缩为 ZIP", icon: "doc.zipper", action: #selector(compressZipAction(_:)))
                addItem(to: submenu, title: "将当前文件夹压缩为 TAR.ZST", icon: "bolt.fill", action: #selector(compressTarZstAction(_:)))
                submenu.addItem(.separator())
            }
            addItem(to: submenu, title: "打开 BoltZip 工作台", icon: "macwindow", action: #selector(openWorkspaceAction(_:)))
        } else {
            if hasArchives {
                addItem(to: submenu, title: "智能解压到当前位置", icon: "arrow.down.doc.fill", action: #selector(smartExtractAction(_:)))
                addItem(to: submenu, title: "解压到同名文件夹", icon: "folder.badge.gearshape", action: #selector(extractSubfolderAction(_:)))
                if targets.count == 1 {
                    addItem(to: submenu, title: "在 BoltZip 中打开浏览", icon: "eye.fill", action: #selector(openArchiveAction(_:)))
                    addItem(to: submenu, title: "校验压缩包完整性", icon: "checkmark.shield.fill", action: #selector(testIntegrityAction(_:)))
                }
                if !onlyArchives {
                    submenu.addItem(.separator())
                }
            }

            if !onlyArchives {
                if hasArchives { submenu.addItem(.separator()) }
                addItem(to: submenu, title: "压缩为 ZIP", icon: "doc.zipper", action: #selector(compressZipAction(_:)))
                addItem(to: submenu, title: "压缩为 TAR.ZST (Zstd)", icon: "bolt.fill", action: #selector(compressTarZstAction(_:)))
                addItem(to: submenu, title: "压缩为 7z", icon: "archivebox.fill", action: #selector(compress7zAction(_:)))
                submenu.addItem(.separator())
                addItem(to: submenu, title: "加密 / 分卷高级压缩...", icon: "lock.shield.fill", action: #selector(compressWizardAction(_:)))
            } else {
                submenu.addItem(.separator())
                addItem(to: submenu, title: "重新打包 / 加密压缩...", icon: "lock.shield.fill", action: #selector(compressWizardAction(_:)))
            }
        }

        boltItem.submenu = submenu
        rootMenu.addItem(boltItem)
        return rootMenu
    }

    private func addItem(to menu: NSMenu, title: String, icon: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            img.isTemplate = true
            item.image = img
        }
        menu.addItem(item)
    }

    /// Renders a 16×16 template circular badge punched with BoltZip's tilted Z-shaped lightning bolt.
    private func makeBoltCircleMenuImage() -> NSImage {
        let side: CGFloat = 16
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let combined = CGMutablePath()
            let circleRect = CGRect(x: 1.0, y: 1.0, width: 14.0, height: 14.0)
            combined.addEllipse(in: circleRect)

            // Normalized Z-bolt coordinates matching BoltZip's AppIcon emblem, centered cleanly inside the circle.
            let span: CGFloat = 14.2
            let ox = (side - span) * 0.5
            let oy = (side - span) * 0.5
            let rawPoints: [(CGFloat, CGFloat)] = [
                (0.33, 0.78),
                (0.78, 0.78),
                (0.51, 0.53),
                (0.65, 0.53),
                (0.42, 0.33),
                (0.72, 0.33),
                (0.67, 0.21),
                (0.21, 0.21),
                (0.48, 0.46),
                (0.34, 0.46),
                (0.57, 0.66),
                (0.28, 0.66)
            ]

            let zPath = CGMutablePath()
            for (idx, pt) in rawPoints.enumerated() {
                let point = CGPoint(x: ox + pt.0 * span, y: oy + pt.1 * span)
                if idx == 0 {
                    zPath.move(to: point)
                } else {
                    zPath.addLine(to: point)
                }
            }
            zPath.closeSubpath()

            var tilt = CGAffineTransform(translationX: side * 0.5, y: side * 0.5)
                .rotated(by: -0.11)
                .translatedBy(x: -side * 0.5, y: -side * 0.5)
            if let tiltedBolt = zPath.copy(using: &tilt) {
                combined.addPath(tiltedBolt)
            }

            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(combined)
            ctx.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        return image
    }

    private func currentTargetURLs() -> [URL] {
        let ctrl = FIFinderSyncController.default()
        if let selected = ctrl.selectedItemURLs(), !selected.isEmpty {
            return selected
        }
        if let targeted = ctrl.targetedURL() {
            return [targeted]
        }
        return []
    }

    private func isArchiveURL(_ url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tar.zst") || lower.hasSuffix(".tar.xz")
            || lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tar.lz4") {
            return true
        }
        let ext = url.pathExtension.lowercased()
        if Self.archiveExtensions.contains(ext) {
            return true
        }
        if ext.count >= 2 && ext.hasPrefix("z") && Int(ext.dropFirst()) != nil {
            return true
        }
        if ext.count == 3 && ext.hasPrefix("r") && Int(ext.dropFirst()) != nil {
            return true
        }
        return false
    }

    // MARK: - Actions

    @objc private func smartExtractAction(_ sender: Any?) { dispatch(op: "smartExtract", host: "hud") }
    @objc private func extractSubfolderAction(_ sender: Any?) { dispatch(op: "extractSubfolder", host: "hud") }
    @objc private func openArchiveAction(_ sender: Any?) { dispatch(op: "open", host: "finder") }
    @objc private func testIntegrityAction(_ sender: Any?) { dispatch(op: "testIntegrity", host: "finder") }
    @objc private func compressZipAction(_ sender: Any?) { dispatch(op: "compressZip", host: "hud") }
    @objc private func compressTarZstAction(_ sender: Any?) { dispatch(op: "compressTarZst", host: "hud") }
    @objc private func compress7zAction(_ sender: Any?) { dispatch(op: "compress7z", host: "hud") }
    @objc private func compressWizardAction(_ sender: Any?) { dispatch(op: "compressWizard", host: "finder") }
    @objc private func openWorkspaceAction(_ sender: Any?) { dispatch(op: "openWorkspace", host: "finder", includeTargets: false) }

    private func dispatch(op: String, host: String, includeTargets: Bool = true) {
        var comps = URLComponents()
        comps.scheme = "boltzip"
        comps.host = host
        var items: [URLQueryItem] = [URLQueryItem(name: "op", value: op)]
        if includeTargets {
            for url in currentTargetURLs() {
                items.append(URLQueryItem(name: "path", value: url.path))
            }
        }
        comps.queryItems = items
        guard let actionURL = comps.url else { return }
        NSWorkspace.shared.open(actionURL)
    }
}
