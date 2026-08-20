import SwiftUI

struct AppsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Applications").font(.headline)
                    Spacer()
                    Button("Reload") { state.loadApps() }
                        .controlSize(.small)
                }
                TextField("Search apps", text: $state.appSearch)
                    .textFieldStyle(.roundedBorder)

                List(state.filteredApps, selection: Binding(
                    get: { state.selectedApp?.id },
                    set: { id in state.selectedApp = state.apps.first { $0.id == id } }
                )) { app in
                    HStack(spacing: 10) {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 28, height: 28)
                                .cornerRadius(6)
                        } else {
                            Image(systemName: "app")
                                .frame(width: 28, height: 28)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).lineLimit(1)
                            Text(app.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .tag(app.id)
                }
                .listStyle(.sidebar)

                Text("\(state.apps.count) apps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 280)
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.selectedApp?.name ?? "No application selected")
                            .font(.title2.weight(.bold))
                        Text(state.selectedApp?.path ?? "Select an app to scan related files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Scan") { state.scanSelectedApp() }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.selectedApp == nil || state.isScanning)
                }

                if let app = state.selectedApp, app.isProtected {
                    Text("System / Apple app — review carefully before removing.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                ResultsList(items: $state.appScanItems)
            }
            .padding(16)
        }
        .onAppear {
            if state.apps.isEmpty { state.loadApps() }
        }
    }
}
