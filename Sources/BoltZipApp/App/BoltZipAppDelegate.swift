import AppKit
import SwiftUI

/// Forwarding NSWindowDelegate proxy so intercepting `windowShouldClose` preserves any
/// underlying SwiftUI window delegate behaviors cleanly.
@MainActor
final class MainWindowDelegateProxy: NSObject, NSWindowDelegate {
    nonisolated(unsafe) weak var wrappedDelegate: (any NSWindowDelegate)?
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
    private let mainWindowDelegateProxy = MainWindowDelegateProxy()
    private let aboutWindowController = AuxiliaryWindowController()
    private let settingsWindowController = AuxiliaryWindowController()

    weak var mainWindow: NSWindow?
    var openMainWindowHandler: (() -> Void)?

    private var pendingURLs: [URL] = []
    private var suppressMainWindowOnLaunch = false
    private var explicitMainWindowRequested = false
    private var didSettleNormalLaunch = false
    private var windowObserversInstalled = false
    private var keyMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSApp.setActivationPolicy(.regular)
        BoltAppIconRenderer.apply(whiteBackground: viewModel.useWhiteAppIcon)
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
        NSApp.setActivationPolicy(.regular)
        BoltAppIconRenderer.apply(whiteBackground: viewModel.useWhiteAppIcon)
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

        if suppressMainWindowOnLaunch && !explicitMainWindowRequested {
            hideAutoCreatedMainWindow()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, !self.suppressMainWindowOnLaunch else { return }
                self.didSettleNormalLaunch = true
                self.menuManager.pruneIfNeeded(using: self.viewModel.l10n)
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
        NSApp.activate(ignoringOtherApps: true)
        viewModel.handleIncomingURLs(urls)
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
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
                NSApp.activate(ignoringOtherApps: true)
                self?.viewModel.startNewArchivePanel()
            },
            onOpenArchive: { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.viewModel.openArchivePanel()
            },
            onOpenSettings: { [weak self] in
                self?.openSettingsWindow()
            },
            onOpenAbout: { [weak self] in
                self?.openAboutWindow()
            }
        )
        viewModel.onRequestShowMainWindow = { [weak self] in
            self?.showMainWindow()
        }
        viewModel.onRequestOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }
        aboutWindowController.onDidClose = { [weak self] in
            self?.terminateIfIdleAndNoVisibleWindows()
        }
        settingsWindowController.onDidClose = { [weak self] in
            self?.terminateIfIdleAndNoVisibleWindows()
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
            guard mods == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "w" else {
                return event
            }
            if let keyWin = NSApp.keyWindow, self.isMainAppWindow(keyWin), self.viewModel.shouldReturnHomeOnWindowClose() {
                self.viewModel.closeArchive()
                return nil
            }
            NSApp.keyWindow?.performClose(nil)
            return nil
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
            let closingID = (note.object as AnyObject?).map { ObjectIdentifier($0) }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000)
                self?.terminateIfIdleAndNoVisibleWindows(excludingWindowID: closingID)
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

    private func hasVisibleUserWindow(excludingWindowID: ObjectIdentifier? = nil) -> Bool {
        for window in NSApp.windows {
            if let excludingWindowID, ObjectIdentifier(window) == excludingWindowID { continue }
            guard window.isVisible, window.alphaValue > 0.05 else { continue }
            let id = window.identifier?.rawValue ?? ""
            if id == "boltzip.quickhud" || id == "boltzip.compress" || id == "boltzip.main" || id == "boltzip.about" || id == "boltzip.settings" {
                return true
            }
            if window.level == .normal && window.styleMask.contains(.titled) && window.frame.height > 60 {
                return true
            }
        }
        return false
    }

    private func terminateIfIdleAndNoVisibleWindows(excludingWindowID: ObjectIdentifier? = nil) {
        guard viewModel.hudModel.phase == .idle else { return }
        guard !viewModel.isPreparingHUDExtract else { return }
        guard !viewModel.isHUDWindowVisible else { return }
        guard !viewModel.isCompressWindowVisible else { return }
        guard !hasVisibleUserWindow(excludingWindowID: excludingWindowID) else { return }
        NSApp.terminate(nil)
    }

    func registerMainWindow(_ window: NSWindow, openMainAction: @escaping () -> Void) {
        let isFirstRegistration = (window.identifier?.rawValue != "boltzip.main")
        if isFirstRegistration {
            window.identifier = NSUserInterfaceItemIdentifier("boltzip.main")
            window.setContentSize(NSSize(width: 680, height: 430))
        }
        window.isReleasedWhenClosed = false
        if window.isRestorable { window.isRestorable = false }
        self.mainWindow = window
        self.openMainWindowHandler = openMainAction
        ensureMainWindowDelegateProxy(on: window)

        if suppressMainWindowOnLaunch && !explicitMainWindowRequested {
            window.alphaValue = 0
            window.orderOut(nil)
        }
    }

    private func ensureMainWindowDelegateProxy(on window: NSWindow) {
        guard window.delegate !== mainWindowDelegateProxy else { return }
        mainWindowDelegateProxy.wrappedDelegate = window.delegate
        mainWindowDelegateProxy.shouldCloseHandler = { [weak self] _ in
            guard let self else { return true }
            if self.viewModel.shouldReturnHomeOnWindowClose() {
                self.viewModel.closeArchive()
                return false
            }
            return true
        }
        window.delegate = mainWindowDelegateProxy
    }

    func registerSecondaryWindow(_ window: NSWindow, identifier: String) {
        if window.identifier?.rawValue != identifier {
            window.identifier = NSUserInterfaceItemIdentifier(identifier)
        }
        window.isRestorable = false
        if suppressMainWindowOnLaunch && !explicitMainWindowRequested {
            window.alphaValue = 0
            window.orderOut(nil)
        }
    }

    func showMainWindow() {
        explicitMainWindowRequested = true
        suppressMainWindowOnLaunch = false
        NSApp.activate(ignoringOtherApps: true)

        if let existing = mainWindow ?? NSApp.windows.first(where: { isMainAppWindow($0) }) {
            existing.alphaValue = 1
            existing.makeKeyAndOrderFront(nil)
            ensureMainWindowDelegateProxy(on: existing)
            return
        }
        openMainWindowHandler?()
    }

    func openAboutWindow() {
        aboutWindowController.show(
            identifier: "boltzip.about",
            title: viewModel.l10n.aboutMenuTitle,
            contentSize: NSSize(width: 390, height: 356),
            rootView: AboutView(vm: viewModel)
        )
    }

    func openSettingsWindow() {
        settingsWindowController.show(
            identifier: "boltzip.settings",
            title: viewModel.l10n.settingsMenuTitle,
            contentSize: NSSize(width: 500, height: 500),
            rootView: SettingsView(vm: viewModel)
        )
    }

    private func hideAutoCreatedMainWindow() {
        for window in NSApp.windows {
            let id = window.identifier?.rawValue ?? ""
            if id == "boltzip.quickhud" || id == "boltzip.compress" || id == "boltzip.settings" { continue }
            let isAppWindow = id == "boltzip.main" || id == "boltzip.about"
                || (window.level == .normal && window.styleMask.contains(.titled) && window.title.localizedCaseInsensitiveContains("BoltZip"))
            if isAppWindow {
                window.alphaValue = 0
                window.orderOut(nil)
            }
        }
    }
}
