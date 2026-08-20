import Foundation
import AppKit

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard, smart, junk, apps, leftovers, diskMap, large, privacy, maintenance, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .smart: return "Smart Scan"
        case .junk: return "System Junk"
        case .apps: return "Applications"
        case .leftovers: return "Leftovers"
        case .diskMap: return "Disk Map"
        case .large: return "Large & Old"
        case .privacy: return "Privacy"
        case .maintenance: return "Maintenance"
        case .tools: return "All Tools"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .smart: return "sparkles"
        case .junk: return "trash"
        case .apps: return "shippingbox"
        case .leftovers: return "sparkle.magnifyingglass"
        case .diskMap: return "circle.circle"
        case .large: return "folder"
        case .privacy: return "shield"
        case .maintenance: return "bolt"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

struct CleanItem: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let size: Int64
    let reason: String
    let confidence: Confidence
    var isSelected: Bool
    var isProtected: Bool

    enum Confidence: String {
        case high, medium, low
    }

    var sizeHuman: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

struct InstalledApp: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let bundleId: String
    let version: String
    let isProtected: Bool
    var icon: NSImage?
}

struct DiskMapNode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    var children: [DiskMapNode]

    var sizeHuman: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

struct DashboardStats {
    var deviceName: String = "Mac"
    var health: String = "Good"
    var diskTotal: Int64 = 0
    var diskUsed: Int64 = 0
    var diskPercent: Int = 0
    var appCount: Int = 0
    var estimatedReclaim: Int64 = 0

    var diskUsedHuman: String { ByteCountFormatter.string(fromByteCount: diskUsed, countStyle: .file) }
    var diskTotalHuman: String { ByteCountFormatter.string(fromByteCount: diskTotal, countStyle: .file) }
    var estimatedReclaimHuman: String { ByteCountFormatter.string(fromByteCount: estimatedReclaim, countStyle: .file) }
}

struct FeatureTile: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let tab: AppTab
}
