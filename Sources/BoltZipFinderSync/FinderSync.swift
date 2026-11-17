import AppKit
import FinderSync
import Foundation

@objc(FinderSync)
final class FinderSync: FIFinderSync {
    private static let archiveExtensions: Set<String> = [
        "zip", "zipx", "z01", "7z", "tar", "gz", "tgz",
        "zst", "zstd", "tzst", "xz", "txz", "bz2", "tbz2",
        "lz4", "tlz4", "iso", "cab", "xar"
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
        if let icon = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "BoltZip") {
            icon.isTemplate = true
            boltItem.image = icon
        }

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
        return Self.archiveExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Actions

    @objc private func smartExtractAction(_ sender: Any?) { dispatch(op: "smartExtract") }
    @objc private func extractSubfolderAction(_ sender: Any?) { dispatch(op: "extractSubfolder") }
    @objc private func openArchiveAction(_ sender: Any?) { dispatch(op: "open") }
    @objc private func testIntegrityAction(_ sender: Any?) { dispatch(op: "testIntegrity") }
    @objc private func compressZipAction(_ sender: Any?) { dispatch(op: "compressZip") }
    @objc private func compressTarZstAction(_ sender: Any?) { dispatch(op: "compressTarZst") }
    @objc private func compress7zAction(_ sender: Any?) { dispatch(op: "compress7z") }
    @objc private func compressWizardAction(_ sender: Any?) { dispatch(op: "compressWizard") }
    @objc private func openWorkspaceAction(_ sender: Any?) { dispatch(op: "openWorkspace", includeTargets: false) }

    private func dispatch(op: String, includeTargets: Bool = true) {
        var comps = URLComponents()
        comps.scheme = "boltzip"
        comps.host = "finder"
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
