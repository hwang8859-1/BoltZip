import AppKit
import BoltZipCore
import SwiftUI

@MainActor
final class BoltZipAppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = WorkspaceViewModel()
    weak var mainWindow: NSWindow?
    var openMainWindowHandler: (() -> Void)?

    private var pendingURLs: [URL] = []
    private var suppressMainWindowOnLaunch = false
    private var explicitMainWindowRequested = false
    private var didSettleNormalLaunch = false
    private var windowCloseObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSApp.setActivationPolicy(.regular)
        wireLifecycleCallbacks()
        viewModel.configureHUD()
        installWindowCloseObserver()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        wireLifecycleCallbacks()
        viewModel.configureHUD()
        installWindowCloseObserver()

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
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        let allHUDOnly = urls.allSatisfy { WorkspaceViewModel.isHUDOnlyURL($0) }

        if allHUDOnly {
            if !didSettleNormalLaunch && !explicitMainWindowRequested {
                suppressMainWindowOnLaunch = true
                hideAutoCreatedMainWindow()
            }
            wireLifecycleCallbacks()
            viewModel.configureHUD()
            viewModel.handleIncomingURLs(urls)
            // Guard against invalid/empty path URLs that never opened a HUD or main window
            if viewModel.hudModel.phase == .idle && !hasVisibleUserWindow() {
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
        if viewModel.hudModel.phase != .idle || viewModel.isHUDWindowVisible || suppressMainWindowOnLaunch {
            return false
        }
        return true
    }

    private func wireLifecycleCallbacks() {
        viewModel.onRequestShowMainWindow = { [weak self] in
            self?.showMainWindow()
        }
        viewModel.onHUDDidHide = { [weak self] in
            self?.terminateIfIdleAndNoVisibleWindows()
        }
    }

    private func installWindowCloseObserver() {
        guard windowCloseObserver == nil else { return }
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let closingID = (note.object as AnyObject?).map { ObjectIdentifier($0) }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(60))
                self?.terminateIfIdleAndNoVisibleWindows(excludingWindowID: closingID)
            }
        }
    }

    private func hasVisibleUserWindow(excludingWindowID: ObjectIdentifier? = nil) -> Bool {
        for window in NSApp.windows {
            if let excludingWindowID, ObjectIdentifier(window) == excludingWindowID { continue }
            guard window.isVisible, window.alphaValue > 0.05 else { continue }
            let id = window.identifier?.rawValue ?? ""
            if id == "boltzip.quickhud" || id == "boltzip.main" || id == "boltzip.about" {
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
        guard !viewModel.isHUDWindowVisible else { return }
        guard !hasVisibleUserWindow(excludingWindowID: excludingWindowID) else { return }
        NSApp.terminate(nil)
    }

    func registerMainWindow(_ window: NSWindow, openMainAction: @escaping () -> Void) {
        if window.identifier?.rawValue != "boltzip.main" {
            window.identifier = NSUserInterfaceItemIdentifier("boltzip.main")
        }
        window.isRestorable = false
        self.mainWindow = window
        self.openMainWindowHandler = openMainAction

        if suppressMainWindowOnLaunch && !explicitMainWindowRequested {
            window.alphaValue = 0
            window.orderOut(nil)
        }
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

        if let existing = mainWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "boltzip.main" }) {
            existing.alphaValue = 1
            existing.makeKeyAndOrderFront(nil)
            return
        }
        openMainWindowHandler?()
    }

    private func hideAutoCreatedMainWindow() {
        for window in NSApp.windows where window.identifier?.rawValue != "boltzip.quickhud" {
            let id = window.identifier?.rawValue ?? ""
            let isAppWindow = id == "boltzip.main" || id == "boltzip.about"
                || (window.level == .normal && window.styleMask.contains(.titled) && window.title.localizedCaseInsensitiveContains("BoltZip"))
            if isAppWindow {
                window.alphaValue = 0
                window.orderOut(nil)
            }
        }
    }
}

private struct MainWindowLaunchBridge: NSViewRepresentable {
    let onWindowResolved: @MainActor (NSWindow) -> Void

    final class ObserverView: NSView {
        var onResolve: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onResolve?(window)
            }
        }
    }

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView(frame: .zero)
        view.onResolve = onWindowResolved
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onResolve = onWindowResolved
        if let window = nsView.window {
            onWindowResolved(window)
        }
    }
}

@main
struct BoltZipApp: App {
    @NSApplicationDelegateAdaptor(BoltZipAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        @Bindable var vm = appDelegate.viewModel
        let l = vm.l10n
        WindowGroup(id: "main") {
            MainWindowView(vm: vm)
                .background(
                    MainWindowLaunchBridge { window in
                        appDelegate.registerMainWindow(window) {
                            openWindow(id: "main")
                        }
                    }
                )
        }
        .defaultSize(width: 760, height: 480)
        .windowToolbarStyle(.unified)
        .handlesExternalEvents(matching: Set(["finder"]))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(l.aboutMenuTitle) {
                    openWindow(id: "about")
                }
            }

            CommandGroup(replacing: .newItem) {
                Button(l.newArchive) {
                    vm.startNewArchivePanel()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(l.openArchive) {
                    vm.openArchivePanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu(l.layoutMenuTitle) {
                Picker(l.themeLabel, selection: $vm.appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title(l)).tag(theme)
                    }
                }
                if vm.supportsLiquidGlass {
                    Divider()
                    Toggle(l.enableTranslucency, isOn: $vm.isWindowTranslucent)
                }
                Divider()
                Toggle(l.toggleFinderBanner, isOn: $vm.showFinderBanner)
                Toggle(l.toggleFeatureCard, isOn: $vm.showFeatureHighlights)
                Toggle(l.toggleRecentsCard, isOn: $vm.showRecentArchives)
                Toggle(l.toggleSidebarInspector, isOn: $vm.showSidebarInspector)
                Toggle(l.toggleStatusBar, isOn: $vm.showStatusBar)
            }

            CommandMenu(l.smartExtract) {
                Button(l.smartExtract) {
                    vm.triggerSmartExtractNow()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(vm.listing == nil)

                Button(l.verify) {
                    vm.testIntegrity()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(vm.listing == nil)

                Divider()

                Button(l.finderBannerEnabledTitle) {
                    vm.alertMessage = vm.installFinderQuickActions()
                }

                Button(l.extensionSettings) {
                    vm.openFinderExtensionSettings()
                }

                Divider()

                Button(l.benchmark) {
                    vm.activeSheet = .benchmark
                }

                Button(l.showcasePage) {
                    vm.openShowcaseWebsite()
                }
            }
        }

        Window(l.aboutMenuTitle, id: "about") {
            AboutView(vm: vm)
                .background(
                    MainWindowLaunchBridge { window in
                        appDelegate.registerSecondaryWindow(window, identifier: "boltzip.about")
                    }
                )
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .handlesExternalEvents(matching: Set<String>())

        Settings {
            SettingsView(vm: vm)
        }
    }
}
