import AppKit
import BoltZipCore
import SwiftUI

@MainActor
final class BoltZipAppDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: WorkspaceViewModel?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if !pendingURLs.isEmpty, let vm = viewModel {
            let urls = pendingURLs
            pendingURLs.removeAll()
            vm.handleIncomingURLs(urls)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
        if let vm = viewModel {
            vm.handleIncomingURLs(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func flushPending(to vm: WorkspaceViewModel) {
        self.viewModel = vm
        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs.removeAll()
            vm.handleIncomingURLs(urls)
        }
    }
}

@main
struct BoltZipApp: App {
    @NSApplicationDelegateAdaptor(BoltZipAppDelegate.self) private var appDelegate
    @State private var vm = WorkspaceViewModel()

    var body: some Scene {
        let l = vm.l10n
        WindowGroup {
            MainWindowView(vm: vm)
                .onAppear {
                    appDelegate.flushPending(to: vm)
                }
        }
        .defaultSize(width: 760, height: 480)
        .handlesExternalEvents(matching: Set(["*"]))
        .commands {
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
                Toggle(l.enableTranslucency, isOn: $vm.isWindowTranslucent)
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

        Settings {
            SettingsView(vm: vm)
        }
    }
}
