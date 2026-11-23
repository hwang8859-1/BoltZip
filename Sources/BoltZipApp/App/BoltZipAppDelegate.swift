import AppKit
import SwiftUI

/// Forwarding NSWindowDelegate proxy so intercepting `windowShouldClose` preserves any
/// underlying SwiftUI window delegate behaviors cleanly.
@MainActor
final class MainWindowDelegateProxy: NSObject, NSWindowDelegate {
    nonisolated(unsafe) var wrappedDelegate: (any NSWindowDelegate)?
    var shouldCloseHandler: ((NSWindow) -> Bool)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let shouldCloseHandler, !shouldCloseHandler(sender) {
            return false
        }
        return wrappedDelegate?.windowShouldClose?(sender) ?? true
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

@MainActor
final class BoltZipAppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = WorkspaceViewModel()
    private let menuManager = MainMenuManager()
    private var mainWindowDelegateProxies: [ObjectIdentifier: MainWindowDelegateProxy] = [:]

    weak var mainWindow: NSWindow?
    var openMainWindowHandler: (() -> Void)?
    var openAboutWindowHandler: (() -> Void)?

    private var pendingURLs: [URL] = []
    private var suppressMainWindowOnLaunch = false
    private var explicitMainWindowRequested = false
    private var didSettleNormalLaunch = false
    private var windowObserversInstalled = false
    private var keyMonitor: Any?
    private var dockMotionObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        let app = (notification.object as? NSApplication) ?? (NSApp as NSApplication?)
        app?.setActivationPolicy(.regular)
        app?.appearance = viewModel.appTheme.nsAppearance
        wireLifecycleCallbacks()
        viewModel.configureHUD()
        installWindowObservers()
        installKeyboardShortcutMonitor()
        menuManager.installObservers { [weak self] in
            guard let self else { return }
            self.menuManager.pruneIfNeeded(using: self.viewModel.l10n)
        }
        menuManager.schedulePrune(using: viewModel.l10n)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let app = (notification.object as? NSApplication) ?? (NSApp as NSApplication?)
        app?.setActivationPolicy(.regular)
        app?.appearance = viewModel.appTheme.nsAppearance
        viewModel.refreshQuickActionsStatus()
        wireLifecycleCallbacks()
        viewModel.configureHUD()
        installWindowObservers()
        installKeyboardShortcutMonitor()
        menuManager.schedulePrune(using: viewModel.l10n)

        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs.removeAll()
            viewModel.handleIncomingURLs(urls)
        }

        viewModel.refreshAppIcon()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(systemIconAppearanceChanged(_:)),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil
        )
        dockMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.viewModel.refreshAppIcon()
            }
        }

        if suppressMainWindowOnLaunch && !explicitMainWindowRequested {
            hideAutoCreatedMainWindow()
        } else {
            boltActivateAppToForeground(bringing: mainWindow)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, !self.suppressMainWindowOnLaunch else { return }
                self.didSettleNormalLaunch = true
                self.menuManager.pruneIfNeeded(using: self.viewModel.l10n)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, !self.suppressMainWindowOnLaunch else { return }
                self.viewModel.checkForUpdates(userInitiated: false)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        let suppressMain = urls.allSatisfy {
            WorkspaceViewModel.isHUDOnlyURL($0) || WorkspaceViewModel.isStandaloneCompressURL($0)
        }

        if suppressMain {
            if !didSettleNormalLaunch && !explicitMainWindowRequested {
                suppressMainWindowOnLaunch = true
                hideAutoCreatedMainWindow()
            }
            wireLifecycleCallbacks()
            viewModel.configureHUD()
            viewModel.handleIncomingURLs(urls)
            if viewModel.hudModel.phase == .idle
                && !viewModel.isPreparingHUDExtract
                && !viewModel.isCompressWindowVisible
                && !hasVisibleUserWindow() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.terminateIfIdleAndNoVisibleWindows()
                }
            }
            return
        }

        explicitMainWindowRequested = true
        suppressMainWindowOnLaunch = false
        viewModel.handleIncomingURLs(urls)
        showMainWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.explicitMainWindowRequested else { return }
            self.showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    @objc private func systemIconAppearanceChanged(_: Notification) {
        guard viewModel.appIconStyle == .system else { return }
        viewModel.refreshAppIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        if let dockMotionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(dockMotionObserver)
        }
        viewModel.cleanupPreviewTempFiles()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if viewModel.hudModel.phase != .idle
            || viewModel.isPreparingHUDExtract
            || viewModel.isHUDWindowVisible
            || viewModel.isCompressWindowVisible
            || suppressMainWindowOnLaunch {
            return false
        }
        return true
    }

    private func wireLifecycleCallbacks() {
        menuManager.configureActions(
            onNewArchive: { [weak self] in
                boltActivateAppToForeground()
                self?.viewModel.startNewArchivePanel()
            },
            onOpenArchive: { [weak self] in
                boltActivateAppToForeground()
                self?.viewModel.openArchivePanel()
            },
            onRepairZip: { [weak self] in
                boltActivateAppToForeground()
                self?.showMainWindow()
                self?.viewModel.openRecoverZipPanel()
            },
            onCheckUpdates: { [weak self] in
                boltActivateAppToForeground()
                self?.showMainWindow()
                self?.viewModel.checkForUpdates(userInitiated: true)
            },
            onOpenAbout: { [weak self] in
                self?.openAboutWindow()
            }
        )
        viewModel.onRequestShowMainWindow = { [weak self] in
            self?.showMainWindow()
        }
        viewModel.onHUDDidHide = { [weak self] in
            self?.terminateIfIdleAndNoVisibleWindows()
        }
        viewModel.onCompressWindowDidClose = { [weak self] in
            self?.terminateIfIdleAndNoVisibleWindows()
        }
        viewModel.onLanguageChanged = { [weak self] in
            guard let self else { return }
            self.menuManager.schedulePrune(using: self.viewModel.l10n)
        }
    }

    private func installKeyboardShortcutMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

            if mods == .command, key == "w" {
                if let keyWin = NSApp.keyWindow, self.isMainAppWindow(keyWin), self.viewModel.shouldReturnHomeOnWindowClose() {
                    self.viewModel.closeArchive()
                    return nil
                }
                NSApp.keyWindow?.performClose(nil)
                return nil
            }

            // Explorer shortcuts (only when main window is active, archive open, no modal/text input focused)
            guard let keyWin = NSApp.keyWindow,
                  self.isMainAppWindow(keyWin),
                  self.viewModel.listing != nil,
                  self.viewModel.activeSheet == nil,
                  self.viewModel.pendingExtractConflict == nil,
                  self.viewModel.pendingBatchArchiveDrop == nil,
                  self.viewModel.pendingDeleteConfirmation == nil,
                  !self.viewModel.isBusy,
                  !(keyWin.firstResponder is NSTextView) else {
                return event
            }

            if mods == .command && key == "a" {
                self.viewModel.selectAllVisibleEntries()
                return nil
            }
            if mods == .command && key == "c" && !self.viewModel.selectedEntryIDs.isEmpty {
                self.viewModel.copySelectedEntryNames()
                return nil
            }
            let isDeleteKey = event.keyCode == 51 || event.keyCode == 117
            if isDeleteKey && (mods.isEmpty || mods == .command) && !self.viewModel.selectedEntryIDs.isEmpty {
                self.viewModel.requestDeleteSelectedEntries()
                return nil
            }
            return event
        }
    }

    private func installWindowObservers() {
        guard !windowObserversInstalled else { return }
        windowObserversInstalled = true
        let nc = NotificationCenter.default

        nc.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let closingWindow = note.object as? NSWindow
            // Delay termination checks briefly so closing windows finish ordering out (`isVisible == false`),
            // without blindly excluding an NSWindow instance that SwiftUI immediately recycles and shows
            // during cold-launch external URL activation (`boltzip://finder?op=open...`).
            Task { @MainActor [weak self, weak closingWindow] in
                if let closingWindow, let self {
                    let key = ObjectIdentifier(closingWindow)
                    if let proxy = self.mainWindowDelegateProxies.removeValue(forKey: key) {
                        if closingWindow.delegate === proxy {
                            closingWindow.delegate = proxy.wrappedDelegate
                        }
                        proxy.wrappedDelegate = nil
                    }
                }
                try? await Task.sleep(for: .milliseconds(60))
                self?.terminateIfIdleAndNoVisibleWindows()
            }
        }

        let proxyCheckNames: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification
        ]
        for name in proxyCheckNames {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let win = note.object as? NSWindow else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.isMainAppWindow(win) else { return }
                    self.ensureMainWindowDelegateProxy(on: win)
                }
            }
        }
    }

    private func isMainAppWindow(_ window: NSWindow) -> Bool {
        if window === mainWindow { return true }
        let id = window.identifier?.rawValue ?? ""
        return id == "boltzip.main" || id.hasPrefix("main")
    }

    private func hasVisibleUserWindow() -> Bool {
        for window in NSApp.windows {
            guard window.isVisible, window.alphaValue > 0.05 else { continue }
            let id = window.identifier?.rawValue ?? ""
            if id == "boltzip.quickhud" || id == "boltzip.compress" || id == "boltzip.main" || id == "boltzip.about" {
                return true
            }
            if window.level == .normal && window.styleMask.contains(.titled) && window.frame.height > 60 {
                return true
            }
        }
        return false
    }

    private func terminateIfIdleAndNoVisibleWindows() {
        guard viewModel.hudModel.phase == .idle else { return }
        guard !viewModel.isPreparingHUDExtract else { return }
        guard !viewModel.isHUDWindowVisible else { return }
        guard !viewModel.isCompressWindowVisible else { return }
        guard !hasVisibleUserWindow() else { return }
        NSApp.terminate(nil)
    }

    func registerMainWindow(_ window: NSWindow, openMainAction: @escaping () -> Void) {
        if window.identifier?.rawValue != "boltzip.main" {
            window.identifier = NSUserInterfaceItemIdentifier("boltzip.main")
        }
        if window.isRestorable { window.isRestorable = false }
        self.mainWindow = window
        self.openMainWindowHandler = openMainAction
        ensureMainWindowDelegateProxy(on: window)

        presentOrSuppressRegisteredWindow(window)
    }

    private func ensureMainWindowDelegateProxy(on window: NSWindow) {
        if window.delegate is MainWindowDelegateProxy {
            return
        }
        let key = ObjectIdentifier(window)
        let proxy = mainWindowDelegateProxies[key] ?? MainWindowDelegateProxy()
        if let existingDelegate = window.delegate, !(existingDelegate is MainWindowDelegateProxy) {
            proxy.wrappedDelegate = existingDelegate
        }
        proxy.shouldCloseHandler = { [weak self] _ in
            guard let self else { return true }
            if self.viewModel.shouldReturnHomeOnWindowClose() {
                self.viewModel.closeArchive()
                return false
            }
            return true
        }
        mainWindowDelegateProxies[key] = proxy
        window.delegate = proxy
    }

    func registerSecondaryWindow(_ window: NSWindow, identifier: String) {
        if window.identifier?.rawValue != identifier {
            window.identifier = NSUserInterfaceItemIdentifier(identifier)
        }
        window.isRestorable = false
        presentOrSuppressRegisteredWindow(window)
    }

    private func presentOrSuppressRegisteredWindow(_ window: NSWindow) {
        if suppressMainWindowOnLaunch && !explicitMainWindowRequested {
            window.alphaValue = 0
            window.orderOut(nil)
            return
        }
        boltActivateAppToForeground(bringing: window)
        for delay in [0.0, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                guard let self, let window else { return }
                guard !self.suppressMainWindowOnLaunch || self.explicitMainWindowRequested else { return }
                boltActivateAppToForeground(bringing: window)
            }
        }
    }

    func showMainWindow() {
        explicitMainWindowRequested = true
        suppressMainWindowOnLaunch = false

        if let existing = mainWindow ?? NSApp.windows.first(where: { isMainAppWindow($0) }) {
            boltActivateAppToForeground(bringing: existing)
            ensureMainWindowDelegateProxy(on: existing)
            return
        }
        boltActivateAppToForeground()
        openMainWindowHandler?()
    }

    func openAboutWindow() {
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == "boltzip.about" }) {
            boltActivateAppToForeground(bringing: existing)
            return
        }
        boltActivateAppToForeground()
        openAboutWindowHandler?()
    }

    private func hideAutoCreatedMainWindow() {
        for window in NSApp.windows {
            let id = window.identifier?.rawValue ?? ""
            if id == "boltzip.quickhud" || id == "boltzip.compress" { continue }
            let isAppWindow = id == "boltzip.main" || id == "boltzip.about"
                || (window.level == .normal && window.styleMask.contains(.titled) && window.title.localizedCaseInsensitiveContains("BoltZip"))
            if isAppWindow {
                window.alphaValue = 0
                window.orderOut(nil)
            }
        }
    }
}
