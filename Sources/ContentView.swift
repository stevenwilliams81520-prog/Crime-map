import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var postcode = ""
    @State private var showFilter = false
    @State private var showHistory = false
    @FocusState private var postcodeFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            CrimeMapView(model: model)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                topBar
                floatingMessages
                Spacer()
                bottomPanel
            }
        }
        .preferredColorScheme(.dark)
        .tint(.brand)
        .task { await model.start() }
        .sheet(isPresented: $showFilter) { FilterSheet(model: model) }
        .sheet(item: $model.list) { CrimeListSheet(list: $0) }
        .sheet(isPresented: $showHistory) { HistorySheet(store: model.history) }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 6) {
            TextField("Postcode", text: $postcode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($postcodeFocused)
                .onSubmit(search)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line))

            Button(action: search) {
                Text("Go").bold()
                    .frame(width: 52, height: 44)
                    .background(Color.brand, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.white)
            }

            Button {
                postcodeFocused = false
                Task { await model.useMyLocation() }
            } label: {
                Image(systemName: "location.fill")
                    .frame(width: 44, height: 44)
                    .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line))
            }
            .accessibilityLabel("Use my location")
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var floatingMessages: some View {
        if let t = model.toast {
            Text(t)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(uiColor: UIColor(hex: 0xFFD7D8)))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Color(uiColor: UIColor(hex: 0x2A1416)), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.brand))
                .padding(.horizontal, 20)
                .onTapGesture { model.toast = nil }
                .task(id: t) {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if model.toast == t { model.toast = nil }
                }
        } else if model.showSearchHere {
            Button {
                Task { await model.searchHere() }
            } label: {
                Text("Search this area")
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.white))
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            }
        } else if model.centre == nil {
            Text("Search a postcode, tap \(Image(systemName: "location.fill")), or press and hold the map")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    // MARK: Bottom panel

    private var bottomPanel: some View {
        let counts = model.counts
        let categories = counts.keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }

        return VStack(alignment: .leading, spacing: 10) {
            statusLine

            HStack(spacing: 8) {
                Menu {
                    Picker("Month", selection: Binding(get: { model.month },
                                                       set: { model.changeMonth($0) })) {
                        Text("All dates").tag(allDates)
                        Section("Recent") {
                            ForEach(model.months, id: \.self) { m in
                                Text(monthLabel(m)).tag(m)
                            }
                        }
                        if !model.historyMonths.isEmpty {
                            Section("Downloaded history") {
                                ForEach(model.historyMonths, id: \.self) { m in
                                    Text(monthLabel(m)).tag(m)
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text(model.month.isEmpty ? "Month" : monthLabel(model.month))
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color.field, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line))
                }

                Button {
                    showFilter = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Filter").bold()
                        if model.activeTypeCount < CrimeType.allCases.count {
                            Text("(\(model.activeTypeCount))").foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color.field, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line))
                }

                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.field, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line))
                }
                .accessibilityLabel("Download history")
            }

            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(categories, id: \.self) { cat in
                            Button { model.toggle(cat) } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(uiColor: crimeColor(cat))).frame(width: 10, height: 10)
                                    Text(crimeName(cat))
                                    Text("\(counts[cat] ?? 0)").foregroundColor(.secondary)
                                }
                                .font(.footnote)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.field))
                                .overlay(Capsule().stroke(Color.line))
                                .opacity(model.hidden.contains(cat) ? 0.35 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.panel)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.line))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.loading {
            HStack(spacing: 8) {
                ProgressView()
                Text(model.loadingText).foregroundColor(.secondary)
            }
            .font(.subheadline)
        } else if !model.place.isEmpty {
            let shown = model.visible.count
            let total = model.crimes.count
            (Text("\(shown)").bold().foregroundColor(.primary)
             + Text(shown != total ? " of \(total)" : "")
             + Text(" crimes · \(model.place) · \(monthLabel(model.month))"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        } else {
            Text("Choose an area to see recorded crimes")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func search() {
        postcodeFocused = false
        let p = postcode
        Task { await model.searchPostcode(p) }
    }
}
