import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 14) {
                    healthCard
                    statCard(title: "Estimated Storage", value: state.stats.estimatedReclaim > 0 ? state.stats.estimatedReclaimHuman : "—", hint: "Potential reclaim from scans")
                    statCard(title: "Installed Apps", value: "\(state.stats.appCount)", hint: "/Applications & ~/Applications") {
                        state.selectedTab = .apps
                    }
                }

                HStack {
                    Text("Quick actions").font(.headline)
                    Spacer()
                    Button("Run Smart Scan") { state.selectedTab = .smart; state.smartScan() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(Array(state.featureTiles.prefix(8))) { tile in
                        Button {
                            state.selectedTab = tile.tab
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: tile.icon)
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                Text(tile.title).font(.subheadline.weight(.semibold))
                                Text(tile.description).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Recommendations").font(.headline)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    recCard("trash", "Clean system junk", "Clear caches and logs that are safe to review.") {
                        state.selectedTab = .junk; state.scanJunk()
                    }
                    recCard("sparkle.magnifyingglass", "Remove leftovers", "Delete data left by uninstalled apps.") {
                        state.selectedTab = .leftovers; state.scanOrphans()
                    }
                    recCard("folder", "Find large files", "Locate the biggest space consumers.") {
                        state.selectedTab = .large; state.scanLarge()
                    }
                    recCard("memorychip", "Free up RAM", "Purge inactive memory for more headroom.") {
                        state.selectedTab = .maintenance; state.reduceRAM()
                    }
                }
            }
            .padding(20)
        }
    }

    private var healthCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("MAC HEALTH").font(.caption).foregroundStyle(.secondary)
                Text(state.stats.health)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(healthColor)
                Text(state.stats.deviceName).font(.subheadline).foregroundStyle(.secondary)
                Text("\(state.stats.diskUsedHuman) of \(state.stats.diskTotalHuman) used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(state.stats.diskPercent), total: 100)
                    .tint(healthColor)
            }
            Spacer()
            Image(systemName: "laptopcomputer")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .padding(16)
                .background(Circle().strokeBorder(.quaternary, lineWidth: 2))
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.25), Color.purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func statCard(title: String, value: String, hint: String, action: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title.weight(.bold))
            Text(hint).font(.caption2).foregroundStyle(.tertiary)
            if let action {
                Button("Manage", action: action).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func recCard(_ icon: String, _ title: String, _ body: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(body).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
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
