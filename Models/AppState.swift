import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .dashboard
    @Published var stats = DashboardStats()
    @Published var statusText = "Ready."
    @Published var isScanning = false
    @Published var progress: Double = 0

    @Published var junkItems: [CleanItem] = []
    @Published var orphanItems: [CleanItem] = []
    @Published var largeItems: [CleanItem] = []
    @Published var privacyItems: [CleanItem] = []
    @Published var smartItems: [CleanItem] = []
    @Published var appScanItems: [CleanItem] = []

    @Published var apps: [InstalledApp] = []
    @Published var selectedApp: InstalledApp?
    @Published var appSearch = ""

    @Published var diskMapRoot = "home"
    @Published var diskMapNode: DiskMapNode?
    @Published var diskMapStack: [DiskMapNode] = []

    @Published var showAbout = false
    @Published var confirmTrashPaths: [String]?
    @Published var maintenanceMessage = ""

    private let cancelToken = CancelToken()

    final class CancelToken: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false
        var value: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); _value = newValue; lock.unlock() }
        }
    }

    init() {
        refreshDashboard()
        NotificationCenter.default.addObserver(
            forName: .menuReduceRAM, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reduceRAM() }
        }
        NotificationCenter.default.addObserver(
            forName: .menuEmptyTrash, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.emptyTrash() }
        }
        NotificationCenter.default.addObserver(
            forName: .menuScanJunk, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.selectedTab = .junk
                self?.scanJunk()
            }
        }
    }

    func refreshDashboard() {
        let d = ScannerService.diskStats()
        stats.diskTotal = d.total
        stats.diskUsed = d.used
        stats.diskPercent = d.percent
        stats.health = ScannerService.health(forPercent: d.percent)
        stats.deviceName = ScannerService.computerName()
        if apps.isEmpty {
            Task.detached(priority: .utility) {
                let list = ScannerService.listInstalledApps()
                await MainActor.run {
                    self.apps = list
                    self.stats.appCount = list.count
                }
            }
        } else {
            stats.appCount = apps.count
        }
        // rough estimate from last scans
        let reclaim = (junkItems + orphanItems).filter(\.isSelected).reduce(Int64(0)) { $0 + $1.size }
        stats.estimatedReclaim = reclaim > 0 ? reclaim : stats.estimatedReclaim
        statusText = "Ready."
    }

    func loadApps() {
        statusText = "Loading applications…"
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let list = ScannerService.listInstalledApps()
            await MainActor.run {
                self.apps = list
                self.stats.appCount = list.count
                self.isScanning = false
                self.statusText = "Loaded \(list.count) apps."
            }
        }
    }

    private func runScan(_ label: String, work: @escaping () -> [CleanItem], assign: @escaping ([CleanItem]) -> Void) {
        guard !isScanning else { return }
        cancelToken.value = false
        isScanning = true
        progress = 0.3
        statusText = "\(label)…"
        Task.detached(priority: .userInitiated) {
            let items = work()
            await MainActor.run {
                assign(items)
                let total = items.reduce(Int64(0)) { $0 + $1.size }
                self.statusText = "\(label): \(items.count) · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
                self.isScanning = false
                self.progress = 0
                self.stats.estimatedReclaim = items.filter(\.isSelected).reduce(0) { $0 + $1.size }
                self.refreshDashboard()
            }
        }
    }

    func scanJunk() {
        runScan("Junk scan", work: { ScannerService.scanSystemJunk { self.cancelToken.value } }) { self.junkItems = $0 }
    }

    func scanOrphans() {
        let installed = apps
        runScan("Leftovers", work: { ScannerService.scanOrphans(installed: installed) { self.cancelToken.value } }) { self.orphanItems = $0 }
    }

    func scanLarge() {
        runScan("Large files", work: { ScannerService.scanLargeFiles { self.cancelToken.value } }) { self.largeItems = $0 }
    }

    func scanOld() {
        runScan("Old files", work: { ScannerService.scanOldFiles { self.cancelToken.value } }) { self.largeItems = $0 }
    }

    func scanPrivacy() {
        runScan("Privacy", work: { ScannerService.scanPrivacy { self.cancelToken.value } }) { self.privacyItems = $0 }
    }

    func smartScan() {
        guard !isScanning else { return }
        cancelToken.value = false
        isScanning = true
        statusText = "Smart Scan running…"
        progress = 0.2
        let installed = apps
        Task.detached(priority: .userInitiated) {
            var all: [CleanItem] = []
            all += ScannerService.scanSystemJunk { self.cancelToken.value }
            all += ScannerService.scanOrphans(installed: installed) { self.cancelToken.value }
            all += ScannerService.scanLargeFiles { self.cancelToken.value }
            all += ScannerService.scanPrivacy { self.cancelToken.value }
            // de-dupe
            var seen = Set<String>()
            let unique = all.filter { seen.insert($0.path).inserted }
            await MainActor.run {
                self.smartItems = unique.sorted { $0.size > $1.size }
                self.junkItems = unique // also seed
                let total = unique.reduce(Int64(0)) { $0 + $1.size }
                self.statusText = "Smart Scan: \(unique.count) · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
                self.isScanning = false
                self.progress = 0
                self.refreshDashboard()
            }
        }
    }

    func scanSelectedApp() {
        guard let app = selectedApp else { return }
        runScan("App scan", work: {
            ScannerService.scanApp(path: app.path, bundleId: app.bundleId, name: app.name)
        }) { self.appScanItems = $0 }
    }

    func scanDiskMap() {
        guard !isScanning else { return }
        isScanning = true
        statusText = "Building disk map…"
        let key = diskMapRoot
        Task.detached(priority: .userInitiated) {
            let tree = ScannerService.diskMap(rootKey: key) { self.cancelToken.value }
            await MainActor.run {
                self.diskMapNode = tree
                if let tree {
                    self.diskMapStack = [tree]
                } else {
                    self.diskMapStack = []
                }
                self.isScanning = false
                if let tree {
                    self.statusText = "Disk map: \(tree.sizeHuman)"
                } else {
                    self.statusText = "Disk map failed."
                }
            }
        }
    }

    func cancelScan() {
        cancelToken.value = true
        statusText = "Cancelling…"
    }

    func trashSelected(from items: Binding<[CleanItem]>) {
        let paths = items.wrappedValue.filter { $0.isSelected && !$0.isProtected }.map(\.path)
        guard !paths.isEmpty else { return }
        confirmTrashPaths = paths
    }

    func confirmTrash() {
        guard let paths = confirmTrashPaths else { return }
        confirmTrashPaths = nil
        statusText = "Moving to Trash…"
        Task.detached {
            let result = ScannerService.moveToTrash(paths: paths)
            await MainActor.run {
                self.statusText = "Moved \(result.removed) item(s)."
                self.refreshDashboard()
            }
        }
    }

    func reduceRAM() {
        statusText = "Reducing RAM…"
        Task.detached {
            let msg = ScannerService.reduceRAM()
            await MainActor.run {
                self.maintenanceMessage = msg
                self.statusText = msg
            }
        }
    }

    func emptyTrash() {
        statusText = "Emptying Trash…"
        Task.detached {
            do {
                try ScannerService.emptyTrash()
                await MainActor.run { self.statusText = "Trash emptied." }
            } catch {
                await MainActor.run { self.statusText = error.localizedDescription }
            }
        }
    }

    func runMaintenance(_ name: String) {
        Task.detached {
            let msg: String
            switch name {
            case "dns": msg = ScannerService.flushDNS()
            case "dock": msg = ScannerService.reloadDock()
            case "finder": msg = ScannerService.relaunchFinder()
            case "fda":
                await MainActor.run { ScannerService.openFullDiskAccessSettings() }
                msg = "Opened Full Disk Access settings."
            default: msg = "Done."
            }
            await MainActor.run {
                self.maintenanceMessage = msg
                self.statusText = msg
            }
        }
    }

    var filteredApps: [InstalledApp] {
        let q = appSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return apps }
        return apps.filter { $0.name.lowercased().contains(q) }
    }

    let featureTiles: [FeatureTile] = [
        .init(icon: "sparkles", title: "Smart Scan", description: "Scan everything at once", tab: .smart),
        .init(icon: "trash", title: "System Junk", description: "Caches, logs, temp files", tab: .junk),
        .init(icon: "shippingbox", title: "Uninstaller", description: "Remove apps + support files", tab: .apps),
        .init(icon: "sparkle.magnifyingglass", title: "Leftovers", description: "Orphans from deleted apps", tab: .leftovers),
        .init(icon: "circle.circle", title: "Disk Map", description: "Visualize space usage", tab: .diskMap),
        .init(icon: "folder", title: "Large Files", description: "Find space hogs", tab: .large),
        .init(icon: "shield", title: "Privacy", description: "Browser caches & recents", tab: .privacy),
        .init(icon: "memorychip", title: "Reduce RAM", description: "Purge inactive memory", tab: .maintenance),
        .init(icon: "bolt", title: "Maintenance", description: "DNS, Dock, Finder", tab: .maintenance),
        .init(icon: "wrench.and.screwdriver", title: "All Tools", description: "30+ features", tab: .tools),
    ]
}
