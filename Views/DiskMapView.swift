import SwiftUI

struct DiskMapView: View {
    @EnvironmentObject var state: AppState

    private var current: DiskMapNode? {
        state.diskMapStack.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Disk Map").font(.title2.weight(.bold))
                    Text("Browse folder sizes. Click a row to zoom in.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Root", selection: $state.diskMapRoot) {
                    Text("Home").tag("home")
                    Text("Downloads").tag("downloads")
                    Text("Documents").tag("documents")
                    Text("~/Library").tag("library")
                    Text("/Applications").tag("applications")
                }
                .frame(width: 160)
                Button("Scan Map") { state.scanDiskMap() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isScanning)
                Button("← Back") {
                    if state.diskMapStack.count > 1 {
                        state.diskMapStack.removeLast()
                    }
                }
                .disabled(state.diskMapStack.count <= 1)
            }

            if let current {
                Text(state.diskMapStack.map(\.name).joined(separator: " › "))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 16) {
                    // Simple ring visualization
                    SunburstView(node: current)
                        .frame(width: 320, height: 320)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(current.children.count) items · \(current.sizeHuman)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        List(current.children) { child in
                            Button {
                                if !child.children.isEmpty {
                                    state.diskMapStack.append(child)
                                }
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(color(for: child))
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading) {
                                        Text(child.name).lineLimit(1)
                                        Text(child.path)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(child.sizeHuman)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Reveal in Finder") {
                                    ScannerService.revealInFinder(path: child.path)
                                }
                                Button("Move to Trash…", role: .destructive) {
                                    state.confirmTrashPaths = [child.path]
                                }
                            }
                        }
                        .listStyle(.inset)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No map yet",
                    systemImage: "circle.circle",
                    description: Text("Choose a location and click Scan Map.")
                )
            }
        }
        .padding(20)
    }

    private func color(for node: DiskMapNode) -> Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .cyan, .mint, .indigo]
        let idx = abs(node.name.hashValue) % colors.count
        return colors[idx]
    }
}

struct SunburstView: View {
    let node: DiskMapNode

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let total = max(node.size, 1)
            var angle = -Double.pi / 2
            let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .cyan, .mint, .indigo, .teal, .yellow]

            for (i, child) in node.children.enumerated() {
                let span = Double(child.size) / Double(total) * Double.pi * 2
                let a0 = angle
                let a1 = angle + max(span, 0.01)
                var path = Path()
                path.addArc(center: center, radius: 120, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                path.addArc(center: center, radius: 55, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
                path.closeSubpath()
                context.fill(path, with: .color(colors[i % colors.count].opacity(0.85)))

                // outer ring children
                let gTotal = max(child.size, 1)
                var ga = a0
                for (gi, g) in child.children.enumerated() {
                    let gspan = Double(g.size) / Double(gTotal) * (a1 - a0)
                    let g0 = ga
                    let g1 = ga + max(gspan, 0.008)
                    var gp = Path()
                    gp.addArc(center: center, radius: 150, startAngle: .radians(g0), endAngle: .radians(g1), clockwise: false)
                    gp.addArc(center: center, radius: 122, startAngle: .radians(g1), endAngle: .radians(g0), clockwise: true)
                    gp.closeSubpath()
                    context.fill(gp, with: .color(colors[i % colors.count].opacity(0.5 + Double(gi % 3) * 0.1)))
                    ga = g1
                }
                angle = a1
            }

            // center label background
            let rect = CGRect(x: center.x - 50, y: center.y - 24, width: 100, height: 48)
            context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(.black.opacity(0.01)))
        }
        .overlay {
            VStack(spacing: 4) {
                Text(node.sizeHuman).font(.headline)
                Text(node.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
    }
}
