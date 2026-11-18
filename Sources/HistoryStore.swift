import Foundation
import CoreLocation

struct HistoryPack: Codable, Identifiable {
    let force: String
    let name: String
    let from: String
    let to: String
    let crimes: Int
    let bytes: Int
    let url: String
    let version: String
    var id: String { force }
}

private struct Manifest: Codable {
    let version: String
    let packs: [HistoryPack]
}

struct InstalledPack: Codable, Identifiable {
    let force: String
    let name: String
    let from: String
    let to: String
    let crimes: Int
    let months: [String]
    let minLat: Int, maxLat: Int, minLng: Int, maxLng: Int
    let version: String
    var id: String { force }

    func covers(_ c: CLLocationCoordinate2D) -> Bool {
        let lat = Int(c.latitude * 1e5), lng = Int(c.longitude * 1e5)
        let pad = 3000 // ~3 km
        return lat >= minLat - pad && lat <= maxLat + pad && lng >= minLng - pad && lng <= maxLng + pad
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published var packs: [HistoryPack] = []
    @Published var installed: [String: InstalledPack] = [:]
    @Published var progress: [String: Double] = [:]
    @Published var status: [String: String] = [:]
    @Published var manifestError: String?
    @Published var loadingManifest = false

    private let folder: URL
    private var indexFile: URL { folder.appendingPathComponent("installed.json") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("History", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true   // re-downloadable, keep out of iCloud backups
        try? url.setResourceValues(values)

        if let data = try? Data(contentsOf: indexFile),
           let list = try? JSONDecoder().decode([InstalledPack].self, from: data) {
            installed = Dictionary(uniqueKeysWithValues: list.map { ($0.force, $0) })
        }
    }

    var installedMonths: [String] {
        Set(installed.values.flatMap(\.months)).sorted(by: >)
    }

    var installedList: [InstalledPack] { installed.values.sorted { $0.name < $1.name } }

    func covers(_ c: CLLocationCoordinate2D) -> Bool { installed.values.contains { $0.covers(c) } }

    func dbPath(_ force: String) -> URL { folder.appendingPathComponent("\(force).sqlite") }

    // MARK: Manifest

    func refreshManifest() async {
        guard HistoryConfig.isConfigured, let url = URL(string: HistoryConfig.manifestURL) else {
            manifestError = "History downloads aren’t set up yet."
            return
        }
        loadingManifest = true
        defer { loadingManifest = false }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppError.notFound }
            packs = try JSONDecoder().decode(Manifest.self, from: data).packs
            manifestError = nil
        } catch {
            manifestError = "Couldn’t load the list of downloads. Check your connection and try again."
        }
    }

    // MARK: Download / remove

    func download(_ pack: HistoryPack) async {
        guard HistoryAccess.isUnlocked else { return }
        guard let url = URL(string: pack.url) else { return }
        let force = pack.force
        status[force] = "Downloading"
        progress[force] = 0
        do {
            let tmp = try await Downloader.download(url) { p in
                Task { @MainActor in self.progress[force] = p }
            }
            status[force] = "Unpacking"
            let partial = folder.appendingPathComponent("\(force).sqlite.part")
            let finalURL = dbPath(force)
            try await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: tmp) }
                try Inflate.file(tmp, to: partial)
            }.value

            guard let db = HistoryDB(path: partial.path) else { throw AppError.notFound }
            let m = db.meta()
            guard m["force"] != nil else { throw AppError.notFound }
            let info = InstalledPack(
                force: force,
                name: m["name"] ?? pack.name,
                from: m["from"] ?? pack.from,
                to: m["to"] ?? pack.to,
                crimes: Int(m["crimes"] ?? "") ?? pack.crimes,
                months: (m["months"] ?? "").split(separator: ",").map(String.init),
                minLat: Int(m["minlat"] ?? "") ?? 0, maxLat: Int(m["maxlat"] ?? "") ?? 0,
                minLng: Int(m["minlng"] ?? "") ?? 0, maxLng: Int(m["maxlng"] ?? "") ?? 0,
                version: pack.version)

            let fm = FileManager.default
            if fm.fileExists(atPath: finalURL.path) { try fm.removeItem(at: finalURL) }
            try fm.moveItem(at: partial, to: finalURL)
            installed[force] = info
            saveIndex()
            status[force] = nil
        } catch {
            status[force] = "Failed – tap to retry"
        }
        progress[force] = nil
    }

    func remove(_ force: String) {
        try? FileManager.default.removeItem(at: dbPath(force))
        installed[force] = nil
        saveIndex()
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(Array(installed.values)) {
            try? data.write(to: indexFile, options: .atomic)
        }
    }

    // MARK: Query

    func crimes(near centre: CLLocationCoordinate2D, months wanted: Set<String>, radius: Double = 1609) async -> [Crime] {
        let packs = installed.values.filter { $0.covers(centre) }
        guard !packs.isEmpty, !wanted.isEmpty else { return [] }

        let ints = wanted.compactMap { Int($0.replacingOccurrences(of: "-", with: "")) }
        guard let fromM = ints.min(), let toM = ints.max() else { return [] }
        let dLat = radius / 111_320
        let dLng = dLat / max(cos(centre.latitude * .pi / 180), 0.2)
        let box = (Int((centre.latitude - dLat) * 1e5), Int((centre.latitude + dLat) * 1e5),
                   Int((centre.longitude - dLng) * 1e5), Int((centre.longitude + dLng) * 1e5))
        let paths = packs.map { dbPath($0.force).path }

        return await Task.detached(priority: .userInitiated) {
            var out: [Crime] = []
            for path in paths {
                guard let db = HistoryDB(path: path) else { continue }
                let rows = db.crimes(minLat: box.0, maxLat: box.1, minLng: box.2, maxLng: box.3,
                                     fromMonth: fromM, toMonth: toM)
                out += rows.filter {
                    wanted.contains($0.month) && metresBetween(centre, $0.latitude, $0.longitude) <= radius
                }
            }
            return out
        }.value
    }
}
