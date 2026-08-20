import SwiftUI

struct MaintenanceView: View {
    @EnvironmentObject var state: AppState

    private let tools: [(icon: String, title: String, body: String, action: String)] = [
        ("memorychip", "Reduce RAM", "Purge inactive memory (may ask for admin).", "ram"),
        ("trash", "Empty Trash", "Permanently delete Trash contents.", "trash"),
        ("globe", "Flush DNS Cache", "Reset the system DNS cache.", "dns"),
        ("dock.rectangle", "Reload Dock", "Restart the Dock process.", "dock"),
        ("folder", "Relaunch Finder", "Restart Finder.", "finder"),
        ("lock.shield", "Full Disk Access", "Open Privacy & Security settings.", "fda"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Maintenance").font(.title2.weight(.bold))
                Text("Tune-up tools to keep macOS responsive.")
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(tools, id: \.action) { tool in
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: tool.icon).font(.title)
                            Text(tool.title).font(.headline)
                            Text(tool.body).font(.caption).foregroundStyle(.secondary).frame(minHeight: 32, alignment: .topLeading)
                            Button("Run") {
                                switch tool.action {
                                case "ram": state.reduceRAM()
                                case "trash": state.emptyTrash()
                                default: state.runMaintenance(tool.action)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                if !state.maintenanceMessage.isEmpty {
                    Text(state.maintenanceMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }
}

struct ToolsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("All Tools").font(.title2.weight(.bold))
                Text("Cleanup and maintenance features in one place.")
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(state.featureTiles) { tile in
                        Button {
                            state.selectedTab = tile.tab
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: tile.icon).font(.title2).foregroundStyle(.blue)
                                Text(tile.title).font(.subheadline.weight(.semibold))
                                Text(tile.description).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Permissions") {
                Text("Grant Full Disk Access for best scan coverage.")
                    .foregroundStyle(.secondary)
                Button("Open Full Disk Access Settings") {
                    ScannerService.openFullDiskAccessSettings()
                }
            }
            Section("About") {
                LabeledContent("App", value: "AppCleaner")
                LabeledContent("UI", value: "Native SwiftUI")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 240)
    }
}
