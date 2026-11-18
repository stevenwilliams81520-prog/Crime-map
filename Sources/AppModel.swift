import SwiftUI
import MapKit
import Combine

struct FocusRequest: Equatable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    static func == (a: FocusRequest, b: FocusRequest) -> Bool { a.id == b.id }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var crimes: [Crime] = []
    @Published var hidden: Set<String> = [] {
        didSet { UserDefaults.standard.set(Array(hidden), forKey: "hiddenCrimeTypes") }
    }
    @Published var months: [String] = []
    @Published var month: String = ""
    @Published var centre: CLLocationCoordinate2D?
    @Published var place: String = ""
    @Published var loading = false
    var loadingText: String {
        month == allDates ? "Loading \(months.count + historyMonths.count) months of crimes…" : "Loading crimes…"
    }
    @Published var toast: String?
    @Published var list: CrimeList?
    @Published var focus: FocusRequest?
    @Published var mapCentre: CLLocationCoordinate2D?

    private let location = LocationManager()
    let history = HistoryStore()
    private var historyWatch: AnyCancellable?

    init() {
        hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenCrimeTypes") ?? [])
        historyWatch = history.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// Downloaded months that are older than the live police data.
    var historyMonths: [String] {
        let live = Set(months)
        return history.installedMonths.filter { !live.contains($0) }
    }

    var visible: [Crime] { crimes.filter { !hidden.contains($0.category) } }

    var counts: [String: Int] {
        Dictionary(crimes.map { ($0.category, 1) }, uniquingKeysWith: +)
    }

    var showSearchHere: Bool {
        guard let c = centre, let m = mapCentre else { return false }
        let a = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let b = CLLocation(latitude: m.latitude, longitude: m.longitude)
        return a.distance(from: b) > 900
    }

    // MARK: Loading

    func start() async {
        do {
            months = try await PoliceAPI.months()
            if month.isEmpty { month = months.first ?? "" }
        } catch {
            show(error)
        }
    }

    func load(_ coord: CLLocationCoordinate2D, place newPlace: String) async {
        centre = coord
        focus = FocusRequest(coordinate: coord)
        loading = true
        defer { loading = false }
        let wantHistory: [String]
        let wantLive: [String]
        if month == allDates {
            wantLive = months
            wantHistory = historyMonths
        } else if historyMonths.contains(month) {
            wantLive = []
            wantHistory = [month]
        } else {
            wantLive = [month]
            wantHistory = []
        }

        do {
            var result: [Crime] = []
            var note: String?

            if !wantHistory.isEmpty {
                if history.covers(coord) {
                    result += await history.crimes(near: coord, months: Set(wantHistory))
                } else if wantLive.isEmpty {
                    note = "Your downloaded history doesn’t cover this area. Add its police force in Download history."
                }
            }

            if wantLive.count == 1 {
                result += try await PoliceAPI.crimes(at: coord, month: wantLive[0])
            } else if wantLive.count > 1 {
                let (live, skipped) = try await PoliceAPI.crimes(at: coord, months: wantLive)
                result += live
                if skipped > 0 {
                    note = "\(skipped) month\(skipped == 1 ? "" : "s") couldn’t be loaded (too busy or not published)."
                }
            }

            crimes = month == allDates ? result.sorted { $0.month > $1.month } : result
            place = newPlace
            if let note = note {
                toast = note
            } else if result.isEmpty {
                toast = "No crimes recorded here for that period (or not published yet)."
            } else if result.count > 20_000 {
                toast = "Showing \(result.count) crimes. Use Filter to narrow it down if the map feels slow."
            }
        } catch {
            crimes = []
            place = ""
            show(error)
        }
    }

    func searchPostcode(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let (coord, label) = try await PoliceAPI.postcode(text)
            await load(coord, place: label)
        } catch {
            show(error)
        }
    }

    func useMyLocation() async {
        do {
            let coord = try await location.current()
            await load(coord, place: "Your location")
        } catch {
            show(error)
        }
    }

    func searchHere() async {
        if let m = mapCentre { await load(m, place: "Map area") }
    }

    func changeMonth(_ m: String) {
        month = m
        if let c = centre {
            let p = place.isEmpty ? "Map point" : place
            Task { await load(c, place: p) }
        }
    }

    // MARK: Filters

    func isOn(_ t: CrimeType) -> Bool { !hidden.contains(t.rawValue) }

    func set(_ t: CrimeType, on: Bool) {
        if on { hidden.remove(t.rawValue) } else { hidden.insert(t.rawValue) }
    }

    func toggle(_ category: String) {
        if hidden.contains(category) { hidden.remove(category) } else { hidden.insert(category) }
    }

    func setAll(_ on: Bool) {
        hidden = on ? [] : Set(CrimeType.allCases.map(\.rawValue))
    }

    func toggleGroup(_ g: CrimeGroup) {
        let allOn = g.types.allSatisfy { isOn($0) }
        g.types.forEach { set($0, on: !allOn) }
    }

    var activeTypeCount: Int { CrimeType.allCases.filter { isOn($0) }.count }

    private func show(_ error: Error) {
        toast = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
