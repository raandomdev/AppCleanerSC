import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                detailHeader
                Divider()
                Group {
                    switch state.selectedTab {
                    case .dashboard: DashboardView()
                    case .smart: ResultsTabView(
                        title: "Smart Scan",
                        subtitle: "One-click scan across junk, leftovers, large files, and privacy.",
                        items: $state.smartItems,
                        scanLabel: "Start Smart Scan",
                        onScan: { state.smartScan() }
                    )
                    case .junk: ResultsTabView(
                        title: "System Junk",
                        subtitle: "Caches, logs, Xcode data, and temporary files.",
                        items: $state.junkItems,
                        scanLabel: "Scan Junk",
                        onScan: { state.scanJunk() }
                    )
                    case .apps: AppsView()
                    case .leftovers: ResultsTabView(
                        title: "Leftovers",
                        subtitle: "Orphan files from apps that are no longer installed.",
                        items: $state.orphanItems,
                        scanLabel: "Find Leftovers",
                        onScan: { state.scanOrphans() }
                    )
                    case .diskMap: DiskMapView()
                    case .large: LargeFilesView()
                    case .privacy: ResultsTabView(
                        title: "Privacy",
                        subtitle: "Browser caches and recent-item lists. Review carefully.",
                        items: $state.privacyItems,
                        scanLabel: "Scan Privacy",
                        onScan: { state.scanPrivacy() }
                    )
                    case .maintenance: MaintenanceView()
                    case .tools: ToolsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .alert("Move to Trash?", isPresented: Binding(
            get: { state.confirmTrashPaths != nil },
            set: { if !$0 { state.confirmTrashPaths = nil } }
        )) {
            Button("Cancel", role: .cancel) { state.confirmTrashPaths = nil }
            Button("Move to Trash", role: .destructive) { state.confirmTrash() }
        } message: {
            Text("Move \(state.confirmTrashPaths?.count ?? 0) item(s) to the Trash?")
        }
        .alert("About AppCleaner", isPresented: $state.showAbout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Native SwiftUI cleaner for macOS.\nClean leftovers, system junk, and free RAM.")
        }
        .onAppear { state.refreshDashboard() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("🧹")
                    .font(.system(size: 28))
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AppCleaner").font(.headline)
                    Text("macOS cleaner").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            List(AppTab.allCases, selection: $state.selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 6) {
                Text("Macintosh HD").font(.caption2).foregroundStyle(.secondary)
                ProgressView(value: Double(state.stats.diskPercent), total: 100)
                    .tint(healthColor)
                Text("\(state.stats.diskUsedHuman) / \(state.stats.diskTotalHuman)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private var detailHeader: some View {
        HStack {
            Text(state.selectedTab.title)
                .font(.title2.weight(.bold))
            Spacer()
            Button {
                state.refreshDashboard()
                if state.selectedTab == .apps { state.loadApps() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            ProgressView(value: state.isScanning ? max(state.progress, 0.15) : 0)
                .progressViewStyle(.linear)
                .opacity(state.isScanning ? 1 : 0.3)
            HStack {
                Text(state.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Cancel") { state.cancelScan() }
                    .disabled(!state.isScanning)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var healthColor: Color {
        switch state.stats.health {
        case "Excellent": return .green
        case "Good": return .cyan
        case "Poor": return .orange
        default: return .red
        }
    }
}
