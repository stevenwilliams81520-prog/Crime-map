import SwiftUI

struct HistorySheet: View {
    @ObservedObject var store: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private func mb(_ bytes: Int) -> String {
        bytes >= 1_000_000 ? String(format: "%.0f MB", Double(bytes) / 1e6) : String(format: "%.1f MB", Double(bytes) / 1e6)
    }

    private func years(_ from: String, _ to: String) -> String {
        "\(from.prefix(4))–\(to.prefix(4))"
    }

    private func crimesText(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM crimes", Double(n) / 1e6)
            : n >= 1000 ? "\(n / 1000)k crimes" : "\(n) crimes"
    }

    var body: some View {
        let available = store.packs.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.force.contains(query.lowercased())
        }

        NavigationStack {
            List {
                Section {
                    Text("Download older crime records for a police force, going back to 2010. They’re saved on this iPhone and appear in the month picker under “Downloaded history”.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if !store.installedList.isEmpty {
                    Section("On this iPhone") {
                        ForEach(store.installedList) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                    Text("\(years(p.from, p.to)) · \(crimesText(p.crimes))")
                                        .font(.footnote).foregroundColor(.secondary)
                                }
                                Spacer()
                                if let newer = store.packs.first(where: { $0.force == p.force && $0.version != p.version }) {
                                    Button("Update") { Task { await store.download(newer) } }
                                        .buttonStyle(.bordered)
                                        .disabled(store.progress[p.force] != nil)
                                } else {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { store.remove(p.force) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section {
                    if store.loadingManifest && store.packs.isEmpty {
                        HStack { ProgressView(); Text("Loading forces…").foregroundColor(.secondary) }
                    }
                    if let e = store.manifestError {
                        Text(e).foregroundColor(.secondary)
                    }
                    ForEach(available) { pack in
                        row(pack)
                    }
                } header: {
                    Text("Police forces")
                } footer: {
                    Text("Swipe left on a downloaded force to remove it. Locations are approximate. Contains public sector information licensed under the Open Government Licence v3.0.")
                }
            }
            .searchable(text: $query, prompt: "Search police forces")
            .refreshable { await store.refreshManifest() }
            .task { await store.refreshManifest() }
            .navigationTitle("Download history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.brand)
    }

    @ViewBuilder
    private func row(_ pack: HistoryPack) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name)
                Text("\(years(pack.from, pack.to)) · \(crimesText(pack.crimes)) · \(mb(pack.bytes))")
                    .font(.footnote).foregroundColor(.secondary)
                if let s = store.status[pack.force] {
                    Text(s).font(.caption).foregroundColor(s.hasPrefix("Failed") ? .brand : .secondary)
                }
            }
            Spacer()
            if let p = store.progress[pack.force] {
                ProgressView(value: p).frame(width: 70)
            } else if store.installed[pack.force] != nil {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else {
                Button {
                    Task { await store.download(pack) }
                } label: {
                    Image(systemName: "arrow.down.circle").font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Download \(pack.name)")
            }
        }
    }
}
