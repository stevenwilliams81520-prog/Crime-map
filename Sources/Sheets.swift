import SwiftUI

struct FilterSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let counts = model.counts

        NavigationStack {
            List {
                ForEach(crimeGroups) { group in
                    Section {
                        ForEach(group.types) { type in
                            Toggle(isOn: Binding(get: { model.isOn(type) },
                                                 set: { model.set(type, on: $0) })) {
                                HStack(spacing: 10) {
                                    Circle().fill(Color(uiColor: type.uiColor)).frame(width: 12, height: 12)
                                    Text(type.name)
                                    Spacer()
                                    if !model.place.isEmpty {
                                        Text("\(counts[type.rawValue] ?? 0)")
                                            .monospacedDigit()
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(group.title)
                            Spacer()
                            let allOn = group.types.allSatisfy { model.isOn($0) }
                            Button(allOn ? "Hide all" : "Show all") {
                                model.toggleGroup(group)
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }
            }
            .tint(.brand)
            .navigationTitle("Crime types")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu("Select") {
                        Button("Select all") { model.setAll(true) }
                        Button("Clear all") { model.setAll(false) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct CrimeListSheet: View {
    let list: CrimeList
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(list.crimes) { crime in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color(uiColor: crimeColor(crime.category)))
                        .frame(width: 12, height: 12)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(crimeName(crime.category)).bold()
                        if !crime.street.isEmpty {
                            Text(crime.street).font(.subheadline).foregroundColor(.secondary)
                        }
                        Text(monthLabel(crime.month) + (crime.outcome.map { " · " + $0 } ?? ""))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("\(list.crimes.count) crime\(list.crimes.count == 1 ? "" : "s") here")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .tint(.brand)
    }
}
