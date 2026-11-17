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
        WindowGroup {
            MainWindowView(vm: vm)
                .onAppear {
                    appDelegate.flushPending(to: vm)
                }
        }
        .handlesExternalEvents(matching: Set(["*"]))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建压缩包...") {
                    vm.startNewArchivePanel()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("打开压缩包...") {
                    vm.openArchivePanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("归档操作") {
                Button("智能解压") {
                    vm.triggerSmartExtractNow()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(vm.listing == nil)

                Button("完整性校验") {
                    vm.testIntegrity()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(vm.listing == nil)

                Divider()

                Button("启用访达一级右键菜单 (Bolt >)...") {
                    vm.alertMessage = vm.installFinderQuickActions()
                }

                Button("打开访达扩展系统设置...") {
                    vm.openFinderExtensionSettings()
                }

                Divider()

                Button("本机算法性能跑分...") {
                    vm.activeSheet = .benchmark
                }

                Button("打开展示页面") {
                    vm.openShowcaseWebsite()
                }
            }
        }

        Settings {
            SettingsView(vm: vm)
        }
    }
}
