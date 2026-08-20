import Foundation
import AppKit

enum ScannerService {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static var userLibrary: URL { home.appendingPathComponent("Library") }

    // MARK: - Disk stats

    static func diskStats() -> (total: Int64, used: Int64, free: Int64, percent: Int) {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let free = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            let used = max(0, total - free)
            let percent = total > 0 ? Int(round(Double(used) / Double(total) * 100)) : 0
            return (total, used, free, percent)
        } catch {
            return (0, 0, 0, 0)
        }
    }

    static func health(forPercent percent: Int) -> String {
        switch percent {
        case ...20: return "Excellent"
        case 21...50: return "Good"
        case 51...80: return "Poor"
        default: return "Really Bad"
        }
    }

    static func computerName() -> String {
        Host.current().localizedName ?? "Mac"
    }

    // MARK: - Size helpers

    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
        var total: Int64 = 0
        if let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]),
                      values.isSymbolicLink != true,
                      values.isRegularFile == true,
                      let s = values.fileSize else { continue }
                total += Int64(s)
            }
        }
        return total
    }

    // MARK: - Apps

    static func listInstalledApps() -> [InstalledApp] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications")
        ]
        var apps: [InstalledApp] = []
        let fm = FileManager.default
        let workspace = NSWorkspace.shared

        for root in roots {
            guard let items = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in items where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                let bundle = Bundle(url: url)
                let bid = bundle?.bundleIdentifier ?? ""
                let version = (bundle?.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
                let protected = bid.hasPrefix("com.apple.") || url.path.hasPrefix("/System")
                let icon = workspace.icon(forFile: url.path)
                icon.size = NSSize(width: 32, height: 32)
                apps.append(InstalledApp(
                    id: url.path,
                    name: name,
                    path: url.path,
                    bundleId: bid,
                    version: version,
                    isProtected: protected,
                    icon: icon
                ))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Junk

    static func scanSystemJunk(cancel: () -> Bool = { false }) -> [CleanItem] {
        let candidates: [(URL, String, CleanItem.Confidence)] = [
            (userLibrary.appendingPathComponent("Caches"), "user cache", .high),
            (userLibrary.appendingPathComponent("Logs"), "user log", .high),
            (URL(fileURLWithPath: "/Library/Caches"), "system cache", .medium),
            (URL(fileURLWithPath: "/Library/Logs"), "system log", .medium),
            (userLibrary.appendingPathComponent("Developer/Xcode/DerivedData"), "Xcode DerivedData", .high),
            (userLibrary.appendingPathComponent("Developer/Xcode/Archives"), "Xcode Archives", .medium),
            (userLibrary.appendingPathComponent("Developer/CoreSimulator/Caches"), "Simulator caches", .high),
            (userLibrary.appendingPathComponent("Logs/DiagnosticReports"), "diagnostic reports", .medium),
        ]

        var items: [CleanItem] = []
        for (url, reason, conf) in candidates {
            if cancel() { break }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            // list immediate children for safer selection
            if let children = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for child in children {
                    if cancel() { break }
                    let s = size(of: child)
                    guard s > 64 * 1024 else { continue }
                    items.append(CleanItem(
                        path: child.path,
                        size: s,
                        reason: reason,
                        confidence: conf,
                        isSelected: conf == .high && s > 10 * 1024 * 1024,
                        isProtected: child.path.hasPrefix("/System")
                    ))
                }
            } else {
                let s = size(of: url)
                if s > 64 * 1024 {
                    items.append(CleanItem(
                        path: url.path, size: s, reason: reason, confidence: conf,
                        isSelected: conf == .high, isProtected: false
                    ))
                }
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    // MARK: - Orphans

    static func scanOrphans(installed: [InstalledApp], cancel: () -> Bool = { false }) -> [CleanItem] {
        let knownNames = Set(installed.map { $0.name.lowercased() })
        let knownIds = Set(installed.map { $0.bundleId.lowercased() }.filter { !$0.isEmpty })

        let roots = [
            userLibrary.appendingPathComponent("Application Support"),
            userLibrary.appendingPathComponent("Caches"),
            userLibrary.appendingPathComponent("Preferences"),
            userLibrary.appendingPathComponent("Containers"),
            userLibrary.appendingPathComponent("Saved Application State"),
        ]

        var items: [CleanItem] = []
        for root in roots {
            if cancel() { break }
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                if cancel() { break }
                let name = child.deletingPathExtension().lastPathComponent
                let lower = name.lowercased()
                // skip if matches known app
                let matched = knownNames.contains(where: { lower.contains($0) || $0.contains(lower) })
                    || knownIds.contains(where: { lower.contains($0) })
                if matched { continue }
                // skip Apple
                if lower.hasPrefix("com.apple") || lower.hasPrefix("apple") { continue }

                let s = size(of: child)
                guard s > 32 * 1024 else { continue }
                items.append(CleanItem(
                    path: child.path,
                    size: s,
                    reason: "possible leftover",
                    confidence: .low,
                    isSelected: false,
                    isProtected: false
                ))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    // MARK: - Large / old / privacy

    static func scanLargeFiles(cancel: () -> Bool = { false }) -> [CleanItem] {
        let roots = ["Downloads", "Documents", "Desktop", "Movies"].map {
            home.appendingPathComponent($0)
        }
        return collectFiles(in: roots, minSize: 20 * 1024 * 1024, maxItems: 150, reason: "large file", cancel: cancel)
    }

    static func scanOldFiles(cancel: () -> Bool = { false }) -> [CleanItem] {
        let roots = ["Downloads", "Documents", "Desktop"].map { home.appendingPathComponent($0) }
        let cutoff = Date().addingTimeInterval(-180 * 24 * 3600)
        var items: [CleanItem] = []
        let fm = FileManager.default
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            var depthNote = 0
            for case let fileURL as URL in enumerator {
                if cancel() { return items }
                // limit depth roughly
                let rel = fileURL.path.replacingOccurrences(of: root.path, with: "")
                if rel.split(separator: "/").count > 3 {
                    enumerator.skipDescendants()
                    continue
                }
                guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      vals.isRegularFile == true,
                      let size = vals.fileSize, size > 1_000_000,
                      let mod = vals.contentModificationDate, mod < cutoff else { continue }
                items.append(CleanItem(
                    path: fileURL.path, size: Int64(size), reason: "not modified in ~6 months",
                    confidence: .low, isSelected: false, isProtected: false
                ))
                depthNote += 1
                if items.count >= 150 { return items.sorted { $0.size > $1.size } }
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    static func scanPrivacy(cancel: () -> Bool = { false }) -> [CleanItem] {
        let candidates: [(URL, String)] = [
            (userLibrary.appendingPathComponent("Caches/com.apple.Safari"), "Safari cache"),
            (userLibrary.appendingPathComponent("Cookies"), "cookies"),
            (userLibrary.appendingPathComponent("Application Support/Google/Chrome/Default/Cache"), "Chrome cache"),
            (userLibrary.appendingPathComponent("Application Support/Google/Chrome/Default/Code Cache"), "Chrome code cache"),
            (userLibrary.appendingPathComponent("Application Support/com.apple.sharedfilelist"), "recent items list"),
        ]
        var items: [CleanItem] = []
        for (url, reason) in candidates {
            if cancel() { break }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let s = size(of: url)
            guard s > 4096 else { continue }
            items.append(CleanItem(
                path: url.path, size: s, reason: reason,
                confidence: reason.contains("cache") ? .medium : .low,
                isSelected: reason.contains("cache"),
                isProtected: false
            ))
        }
        return items.sorted { $0.size > $1.size }
    }

    static func collectFiles(in roots: [URL], minSize: Int64, maxItems: Int, reason: String, cancel: () -> Bool) -> [CleanItem] {
        var items: [CleanItem] = []
        let fm = FileManager.default
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                if cancel() { return items.sorted { $0.size > $1.size } }
                guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      vals.isRegularFile == true,
                      let s = vals.fileSize, Int64(s) >= minSize else { continue }
                items.append(CleanItem(
                    path: fileURL.path, size: Int64(s), reason: reason,
                    confidence: .medium, isSelected: Int64(s) >= 50 * 1024 * 1024, isProtected: false
                ))
                if items.count >= maxItems { return items.sorted { $0.size > $1.size } }
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    // MARK: - Disk map tree

    static func diskMap(rootKey: String, maxDepth: Int = 3, maxChildren: Int = 24, cancel: () -> Bool = { false }) -> DiskMapNode? {
        let root: URL
        switch rootKey {
        case "downloads": root = home.appendingPathComponent("Downloads")
        case "documents": root = home.appendingPathComponent("Documents")
        case "library": root = userLibrary
        case "applications": root = URL(fileURLWithPath: "/Applications")
        default: root = home
        }
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        return buildNode(url: root, depth: 0, maxDepth: maxDepth, maxChildren: maxChildren, cancel: cancel)
    }

    private static func buildNode(url: URL, depth: Int, maxDepth: Int, maxChildren: Int, cancel: () -> Bool) -> DiskMapNode {
        if cancel() {
            return DiskMapNode(name: url.lastPathComponent, path: url.path, size: 0, children: [])
        }
        var children: [DiskMapNode] = []
        var total: Int64 = 0
        var filesBucket: Int64 = 0
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return DiskMapNode(name: url.lastPathComponent, path: url.path, size: 0, children: [])
        }
        for entry in entries {
            if cancel() { break }
            guard let vals = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]),
                  vals.isSymbolicLink != true else { continue }
            if vals.isDirectory == true {
                if depth >= maxDepth {
                    let s = size(of: entry)
                    total += s
                    children.append(DiskMapNode(name: entry.lastPathComponent, path: entry.path, size: s, children: []))
                } else {
                    let node = buildNode(url: entry, depth: depth + 1, maxDepth: maxDepth, maxChildren: maxChildren, cancel: cancel)
                    total += node.size
                    if node.size > 0 { children.append(node) }
                }
            } else {
                filesBucket += Int64(vals.fileSize ?? 0)
            }
        }
        total += filesBucket
        if filesBucket > 0 && depth < maxDepth {
            children.append(DiskMapNode(name: "(files)", path: url.path, size: filesBucket, children: []))
        }
        children.sort { $0.size > $1.size }
        if children.count > maxChildren {
            let rest = children[maxChildren...]
            let restSize = rest.reduce(Int64(0)) { $0 + $1.size }
            children = Array(children.prefix(maxChildren))
            if restSize > 0 {
                children.append(DiskMapNode(name: "(+\(rest.count) more)", path: url.path, size: restSize, children: []))
            }
        }
        return DiskMapNode(name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, path: url.path, size: total, children: children)
    }

    // MARK: - App related files

    static func scanApp(path: String, bundleId: String, name: String) -> [CleanItem] {
        var items: [CleanItem] = []
        let appURL = URL(fileURLWithPath: path)
        // include the app itself
        items.append(CleanItem(
            path: path, size: size(of: appURL), reason: "application",
            confidence: .high, isSelected: true, isProtected: false
        ))

        let needles = [name, bundleId].filter { !$0.isEmpty }
        let searchRoots = [
            userLibrary.appendingPathComponent("Application Support"),
            userLibrary.appendingPathComponent("Caches"),
            userLibrary.appendingPathComponent("Preferences"),
            userLibrary.appendingPathComponent("Containers"),
            userLibrary.appendingPathComponent("Saved Application State"),
            userLibrary.appendingPathComponent("Logs"),
        ]
        for root in searchRoots {
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                let lower = child.lastPathComponent.lowercased()
                let match = needles.contains { n in lower.contains(n.lowercased()) }
                guard match else { continue }
                let s = size(of: child)
                items.append(CleanItem(
                    path: child.path, size: s, reason: root.lastPathComponent,
                    confidence: .medium, isSelected: true, isProtected: false
                ))
            }
        }
        return items
    }

    // MARK: - Removal / maintenance

    static func moveToTrash(paths: [String]) -> (removed: Int, errors: [String]) {
        var removed = 0
        var errors: [String] = []
        for path in paths {
            if path.hasPrefix("/System") || path.hasPrefix("/usr") || path.hasPrefix("/bin") {
                errors.append("Protected: \(path)")
                continue
            }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                removed += 1
            } catch {
                errors.append("\(path): \(error.localizedDescription)")
            }
        }
        return (removed, errors)
    }

    static func emptyTrash() throws {
        let script = "tell application \"Finder\" to empty trash"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "AppCleaner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not empty Trash"])
        }
    }

    static func reduceRAM() -> String {
        // `purge` requires root; try via osascript admin prompt
        let script = "do shell script \"purge\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return "Inactive memory purged."
            }
            return "Could not run purge (permission denied or cancelled)."
        } catch {
            return "Reduce RAM failed: \(error.localizedDescription)"
        }
    }

    static func flushDNS() -> String {
        let p1 = Process()
        p1.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        p1.arguments = ["-flushcache"]
        try? p1.run(); p1.waitUntilExit()
        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p2.arguments = ["-HUP", "mDNSResponder"]
        try? p2.run(); p2.waitUntilExit()
        return "DNS cache flushed."
    }

    static func reloadDock() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Dock"]
        try? p.run(); p.waitUntilExit()
        return "Dock reloaded."
    }

    static func relaunchFinder() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Finder"]
        try? p.run(); p.waitUntilExit()
        return "Finder relaunched."
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
