import AppKit
import SwiftUI

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
        let vm = appDelegate.viewModel
        let l = L10n(language: vm.appLanguage)
        Window("BoltZip", id: "main") {
            MainWindowView(vm: vm)
                .background(
                    MainWindowLaunchBridge { window in
                        appDelegate.openAboutWindowHandler = {
                            openWindow(id: "about")
                        }
                        appDelegate.registerMainWindow(window) {
                            openWindow(id: "main")
                        }
                    }
                )
        }
        .defaultSize(width: 720, height: 520)
        .windowToolbarStyle(.unifiedCompact)
        .handlesExternalEvents(matching: Set(["*"]))
        .commands {
            CommandGroup(replacing: .appInfo) {}
            CommandGroup(replacing: .appVisibility) {}
            CommandGroup(replacing: .systemServices) {}
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .importExport) {}
            CommandGroup(replacing: .undoRedo) {}
        }
        .commands {
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .windowSize) {}
            CommandGroup(replacing: .windowList) {}
            CommandGroup(replacing: .help) {}
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
        .windowToolbarStyle(.unifiedCompact)
        .handlesExternalEvents(matching: Set<String>())

        Settings {
            SettingsView(vm: vm)
        }
    }
}
