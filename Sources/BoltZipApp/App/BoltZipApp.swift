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

    var body: some Scene {
        let vm = appDelegate.viewModel
        WindowGroup {
            MainWindowView(vm: vm)
                .background(
                    MainWindowLaunchBridge { window in
                        appDelegate.registerMainWindow(window) {
                            appDelegate.showMainWindow()
                        }
                    }
                )
        }
        .windowToolbarStyle(.unifiedCompact)
        .handlesExternalEvents(matching: Set(["finder"]))
        .commands {
            CommandGroup(replacing: .appInfo) {}
            CommandGroup(replacing: .appVisibility) {}
            CommandGroup(replacing: .systemServices) {}
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .importExport) {}
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .windowSize) {}
            CommandGroup(replacing: .windowList) {}
            CommandGroup(replacing: .help) {}
        }
    }
}
