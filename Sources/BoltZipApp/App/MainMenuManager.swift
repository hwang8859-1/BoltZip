import AppKit
import Foundation

/// Forwarding NSMenuDelegate proxy allowing SwiftUI to update Settings/Quit native items
/// while keeping the merged top-level `BoltZip` menu cleanly ordered in place.
final class ForwardingMenuDelegateProxy: NSObject, NSMenuDelegate {
    nonisolated(unsafe) weak var wrappedDelegate: (any NSMenuDelegate)?
    private let onPostUpdate: @MainActor (NSMenu) -> Void

    init(wrappedDelegate: (any NSMenuDelegate)?, onPostUpdate: @escaping @MainActor (NSMenu) -> Void) {
        self.wrappedDelegate = wrappedDelegate
        self.onPostUpdate = onPostUpdate
        super.init()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        wrappedDelegate?.menuNeedsUpdate?(menu)
        MainActor.assumeIsolated {
            onPostUpdate(menu)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        wrappedDelegate?.menuWillOpen?(menu)
        MainActor.assumeIsolated {
            onPostUpdate(menu)
        }
    }

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return wrappedDelegate?.responds(to: aSelector) ?? false
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let wrappedDelegate, wrappedDelegate.responds(to: aSelector) {
            return wrappedDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }
}

/// Target handling merged top menu bar actions (`新建压缩包`, `打开压缩包`, `修复损坏的 ZIP 归档`, `关于 BoltZip`).
@MainActor
final class MergedMenuActionTarget: NSObject {
    var onNewArchive: (() -> Void)?
    var onOpenArchive: (() -> Void)?
    var onRepairZip: (() -> Void)?
    var onCheckUpdates: (() -> Void)?
    var onOpenAbout: (() -> Void)?

    @objc func performNewArchive(_ sender: Any?) {
        onNewArchive?()
    }

    @objc func performOpenArchive(_ sender: Any?) {
        onOpenArchive?()
    }

    @objc func performRepairZip(_ sender: Any?) {
        onRepairZip?()
    }

    @objc func performCheckUpdates(_ sender: Any?) {
        onCheckUpdates?()
    }

    @objc func performOpenAbout(_ sender: Any?) {
        onOpenAbout?()
    }
}

/// Consolidates the macOS menu bar into a single `BoltZip` menu after `` with exact order:
/// 1. 新建压缩包 (⌘N)
/// 2. 打开压缩包 (⌘O)
/// 3. 修复损坏的 ZIP 归档… (⌥⌘R)
/// 4. 设置… (⌘,)
/// 5. 检查更新…
/// 6. 关于 BoltZip
/// 7. 退出 BoltZip (⌘Q)
@MainActor
final class MainMenuManager {
    private var observersInstalled = false
    private var isPruning = false
    private var pruneGeneration = 0
    private var proxy: ForwardingMenuDelegateProxy?

    private let actionTarget = MergedMenuActionTarget()
    private lazy var newArchiveItem: NSMenuItem = {
        let item = NSMenuItem(title: "", action: #selector(MergedMenuActionTarget.performNewArchive(_:)), keyEquivalent: "n")
        item.keyEquivalentModifierMask = .command
        item.target = actionTarget
        return item
    }()
    private lazy var openArchiveItem: NSMenuItem = {
        let item = NSMenuItem(title: "", action: #selector(MergedMenuActionTarget.performOpenArchive(_:)), keyEquivalent: "o")
        item.keyEquivalentModifierMask = .command
        item.target = actionTarget
        return item
    }()
    private lazy var repairZipItem: NSMenuItem = {
        let item = NSMenuItem(title: "", action: #selector(MergedMenuActionTarget.performRepairZip(_:)), keyEquivalent: "r")
        item.keyEquivalentModifierMask = [.command, .option]
        item.target = actionTarget
        return item
    }()
    private lazy var checkUpdatesItem: NSMenuItem = {
        let item = NSMenuItem(title: "", action: #selector(MergedMenuActionTarget.performCheckUpdates(_:)), keyEquivalent: "")
        item.target = actionTarget
        return item
    }()
    private lazy var aboutItem: NSMenuItem = {
        let item = NSMenuItem(title: "", action: #selector(MergedMenuActionTarget.performOpenAbout(_:)), keyEquivalent: "")
        item.target = actionTarget
        return item
    }()
    private let actionsSeparator = NSMenuItem.separator()
    private let quitSeparator = NSMenuItem.separator()

    func configureActions(
        onNewArchive: @escaping () -> Void,
        onOpenArchive: @escaping () -> Void,
        onRepairZip: @escaping () -> Void,
        onCheckUpdates: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void
    ) {
        actionTarget.onNewArchive = onNewArchive
        actionTarget.onOpenArchive = onOpenArchive
        actionTarget.onRepairZip = onRepairZip
        actionTarget.onCheckUpdates = onCheckUpdates
        actionTarget.onOpenAbout = onOpenAbout
    }

    func installObservers(onMenuPruneNeeded: @escaping @MainActor () -> Void) {
        guard !observersInstalled else { return }
        observersInstalled = true
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didFinishLaunchingNotification,
            NSApplication.didBecomeActiveNotification,
            NSWindow.didBecomeKeyNotification
        ]
        for name in names {
            nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    onMenuPruneNeeded()
                }
            }
        }
    }

    func schedulePrune(using l: L10n) {
        pruneGeneration &+= 1
        let gen = pruneGeneration
        pruneIfNeeded(using: l)
        for delay in [0.08, 0.35, 0.9, 1.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.pruneGeneration == gen else { return }
                self.pruneIfNeeded(using: l)
            }
        }
    }

    func pruneIfNeeded(using l: L10n) {
        guard !isPruning, let app = NSApp as NSApplication?, let mainMenu = app.mainMenu, !mainMenu.items.isEmpty else { return }
        isPruning = true
        defer { isPruning = false }

        if app.windowsMenu != nil { app.windowsMenu = nil }
        if app.servicesMenu != nil { app.servicesMenu = nil }
        if app.helpMenu != nil { app.helpMenu = nil }

        guard let appItem = mainMenu.items.first, let appSubmenu = appItem.submenu else { return }
        if appItem.title != "BoltZip" { appItem.title = "BoltZip" }
        if appSubmenu.title != "BoltZip" { appSubmenu.title = "BoltZip" }

        if proxy == nil || appSubmenu.delegate !== proxy {
            let wrapped = (appSubmenu.delegate as? ForwardingMenuDelegateProxy)?.wrappedDelegate ?? appSubmenu.delegate
            let created = ForwardingMenuDelegateProxy(wrappedDelegate: wrapped) { [weak self] menu in
                self?.syncMergedAppMenu(menu, l: l)
            }
            proxy = created
            appSubmenu.delegate = created
        }

        syncMergedAppMenu(appSubmenu, l: l)

        // Merge: keep strictly ONE top-level menu (`BoltZip`) next to Apple menu
        for item in mainMenu.items.reversed() where item !== appItem {
            mainMenu.removeItem(item)
        }
    }

    private func syncMergedAppMenu(_ submenu: NSMenu, l: L10n) {
        if newArchiveItem.title != l.newArchive { newArchiveItem.title = l.newArchive }
        if openArchiveItem.title != l.openArchive { openArchiveItem.title = l.openArchive }
        if repairZipItem.title != l.recoverZipMenuTitle { repairZipItem.title = l.recoverZipMenuTitle }
        if checkUpdatesItem.title != l.checkForUpdatesMenuTitle { checkUpdatesItem.title = l.checkForUpdatesMenuTitle }
        if aboutItem.title != l.aboutMenuTitle { aboutItem.title = l.aboutMenuTitle }

        let settingsItem = submenu.items.first { item in
            !item.isAlternate && !item.isSeparatorItem && (
                item.keyEquivalent == ","
                    || item.title.contains("设置")
                    || item.title.contains("設定")
                    || item.title.contains("Settings")
                    || item.title.contains("Preferences")
            )
        }
        let quitItem = submenu.items.first { item in
            !item.isAlternate && !item.isSeparatorItem && (
                item.action == #selector(NSApplication.terminate(_:))
                    || item.keyEquivalent == "q"
            )
        }

        if let settingsItem, settingsItem.title != l.settingsMenuTitle {
            settingsItem.title = l.settingsMenuTitle
        }
        if let quitItem, quitItem.title != l.quitMenuTitle {
            quitItem.title = l.quitMenuTitle
        }

        // Required order: 新建压缩包、打开压缩包、修复损坏的 ZIP 归档，设置，关于，退出
        var desired: [NSMenuItem] = [
            newArchiveItem,
            openArchiveItem,
            repairZipItem,
            actionsSeparator
        ]
        if let settingsItem { desired.append(settingsItem) }
        desired.append(checkUpdatesItem)
        desired.append(aboutItem)
        if let quitItem {
            desired.append(quitSeparator)
            desired.append(quitItem)
        }

        if submenu.items != desired {
            submenu.items = desired
        }
    }
}
