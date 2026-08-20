import SwiftUI
import AppKit

@main
struct AppCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About AppCleaner") {
                    appState.showAbout = true
                }
            }
            CommandMenu("Clean") {
                Button("Scan System Junk") { appState.selectedTab = .junk; appState.scanJunk() }
                Button("Find Leftovers") { appState.selectedTab = .leftovers; appState.scanOrphans() }
                Button("Manage Applications") { appState.selectedTab = .apps }
                Divider()
                Button("Reduce RAM") { appState.reduceRAM() }
                Button("Empty Trash…") { appState.emptyTrash() }
            }
            CommandMenu("View") {
                ForEach(AppTab.allCases) { tab in
                    Button(tab.title) { appState.selectedTab = tab }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "🧹"
            button.toolTip = "AppCleaner"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show AppCleaner", action: #selector(showApp), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Reduce RAM", action: #selector(reduceRAM), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Empty Trash…", action: #selector(emptyTrash), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Scan System Junk", action: #selector(scanJunk), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AppCleaner", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func showApp() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func reduceRAM() {
        showApp()
        NotificationCenter.default.post(name: .menuReduceRAM, object: nil)
    }

    @objc private func emptyTrash() {
        showApp()
        NotificationCenter.default.post(name: .menuEmptyTrash, object: nil)
    }

    @objc private func scanJunk() {
        showApp()
        NotificationCenter.default.post(name: .menuScanJunk, object: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let menuReduceRAM = Notification.Name("menuReduceRAM")
    static let menuEmptyTrash = Notification.Name("menuEmptyTrash")
    static let menuScanJunk = Notification.Name("menuScanJunk")
}
