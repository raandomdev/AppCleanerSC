import SwiftUI

struct ResultsTabView: View {
    @EnvironmentObject var state: AppState
    let title: String
    let subtitle: String
    @Binding var items: [CleanItem]
    let scanLabel: String
    let onScan: () -> Void

    private var selectedCount: Int { items.filter { $0.isSelected && !$0.isProtected }.count }
    private var selectedSize: Int64 { items.filter { $0.isSelected && !$0.isProtected }.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.weight(.bold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(scanLabel, action: onScan)
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isScanning)
            }

            HStack {
                Text(items.isEmpty
                     ? "Not scanned yet."
                     : "\(selectedCount) of \(items.count) selected · \(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Select All") {
                    for i in items.indices where !items[i].isProtected { items[i].isSelected = true }
                }
                .controlSize(.small)
                Button("Deselect") {
                    for i in items.indices { items[i].isSelected = false }
                }
                .controlSize(.small)
                Button("Remove Selected…") {
                    state.trashSelected(from: $items)
                }
                .controlSize(.small)
                .disabled(selectedCount == 0)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "No items",
                    systemImage: "tray",
                    description: Text("Run a scan to find cleanable files.")
                )
            } else {
                List {
                    ForEach($items) { $item in
                        CleanItemRow(item: $item)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
    }
}

struct CleanItemRow: View {
    @Binding var item: CleanItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                if !item.isProtected { item.isSelected.toggle() }
            } label: {
                Image(systemName: item.isProtected ? "lock.fill" : (item.isSelected ? "checkmark.square.fill" : "square"))
                    .foregroundStyle(
                      item.isProtected ? Color.secondary
                      : (item.isSelected ? Color.accentColor : Color.secondary)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.path)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Text(item.confidence.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(confidenceColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(confidenceColor)
                    Text(item.sizeHuman).font(.caption2).foregroundStyle(.secondary)
                    Text(item.reason).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button {
                ScannerService.revealInFinder(path: item.path)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 2)
    }

    private var confidenceColor: Color {
        switch item.confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .secondary
        }
    }
}

struct LargeFilesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Large & Old Files").font(.title2.weight(.bold))
                    Text("Find big files and items you have not touched in a long time.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Scan Large Files") { state.scanLarge() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isScanning)
                Button("Scan Old Files") { state.scanOld() }
                    .disabled(state.isScanning)
            }

            ResultsList(items: $state.largeItems)
        }
        .padding(20)
    }
}

struct ResultsList: View {
    @EnvironmentObject var state: AppState
    @Binding var items: [CleanItem]

    private var selectedCount: Int { items.filter { $0.isSelected && !$0.isProtected }.count }
    private var selectedSize: Int64 { items.filter { $0.isSelected && !$0.isProtected }.reduce(0) { $0 + $1.size } }

    var body: some View {
        HStack {
            Text(items.isEmpty ? "Not scanned yet." : "\(selectedCount) of \(items.count) selected · \(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Select All") {
                for i in items.indices where !items[i].isProtected { items[i].isSelected = true }
            }.controlSize(.small)
            Button("Deselect") {
                for i in items.indices { items[i].isSelected = false }
            }.controlSize(.small)
            Button("Remove Selected…") {
                state.trashSelected(from: $items)
            }
            .controlSize(.small)
            .disabled(selectedCount == 0)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }

        if items.isEmpty {
            ContentUnavailableView("No items", systemImage: "folder", description: Text("Run a scan to begin."))
        } else {
            List {
                ForEach($items) { $item in
                    CleanItemRow(item: $item)
                }
            }
            .listStyle(.inset)
        }
    }
}
