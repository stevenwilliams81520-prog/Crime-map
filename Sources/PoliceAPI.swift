import Foundation
import CoreLocation

enum AppError: LocalizedError {
    case tooMany, notFound, offline, server(Int), postcode, locationDenied

    var errorDescription: String? {
        switch self {
        case .tooMany: return "Too many crimes here to load at once. Try a more specific spot."
        case .notFound: return "Not found."
        case .offline: return "No connection. Check your signal and try again."
        case .server(let code): return "Police data error (\(code)). Try again shortly."
        case .postcode: return "Postcode not found."
        case .locationDenied: return "Location is off for this app. Turn it on in Settings, or use a postcode."
        }
    }
}

private struct APICrime: Decodable {
    struct Street: Decodable { let name: String? }
    struct Location: Decodable {
        let latitude: String
        let longitude: String
        let street: Street?
    }
    struct Outcome: Decodable { let category: String? }

    let category: String
    let location: Location?
    let month: String
    let outcome_status: Outcome?
}

enum PoliceAPI {
    private static func get(_ url: URL) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw AppError.offline
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: return data
        case 503: throw AppError.tooMany
        case 404: throw AppError.notFound
        default: throw AppError.server(code)
        }
    }

    /// Months with published data, newest first.
    static func months() async throws -> [String] {
        struct Entry: Decodable { let date: String }
        let data = try await get(URL(string: "https://data.police.uk/api/crimes-street-dates")!)
        let dates = try JSONDecoder().decode([Entry].self, from: data).map(\.date).sorted(by: >)
        return Array(dates.prefix(36))
    }

    /// All street-level crimes within about a mile of a point.
    static func crimes(at coord: CLLocationCoordinate2D, month: String) async throws -> [Crime] {
        var c = URLComponents(string: "https://data.police.uk/api/crimes-street/all-crime")!
        var items = [
            URLQueryItem(name: "lat", value: String(format: "%.4f", coord.latitude)),
            URLQueryItem(name: "lng", value: String(format: "%.4f", coord.longitude))
        ]
        if !month.isEmpty { items.append(URLQueryItem(name: "date", value: month)) }
        c.queryItems = items
        let data = try await get(c.url!)
        let raw = try JSONDecoder().decode([APICrime].self, from: data)
        return raw.compactMap { r in
            guard let loc = r.location,
                  let lat = Double(loc.latitude),
                  let lng = Double(loc.longitude) else { return nil }
            return Crime(category: r.category,
                         street: loc.street?.name ?? "",
                         month: r.month,
                         outcome: r.outcome_status?.category,
                         latitude: lat,
                         longitude: lng)
        }
    }

    /// Crimes for several months, fetched four at a time.
    /// Months that fail (too busy, not published) are skipped and counted.
    static func crimes(at coord: CLLocationCoordinate2D, months: [String]) async throws -> (crimes: [Crime], skipped: Int) {
        var all: [Crime] = []
        var skipped = 0
        var lastError: Error?
        var start = 0
        while start < months.count {
            let batch = Array(months[start..<min(start + 4, months.count)])
            start += 4
            let results = await withTaskGroup(of: Result<[Crime], Error>.self) { group -> [Result<[Crime], Error>] in
                for m in batch {
                    group.addTask {
                        do { return .success(try await PoliceAPI.crimes(at: coord, month: m)) }
                        catch { return .failure(error) }
                    }
                }
                var out: [Result<[Crime], Error>] = []
                for await r in group { out.append(r) }
                return out
            }
            for r in results {
                switch r {
                case .success(let c): all.append(contentsOf: c)
                case .failure(let e): skipped += 1; lastError = e
                }
            }
        }
        if all.isEmpty, let e = lastError { throw e }
        return (all, skipped)
    }

    /// UK postcode to coordinate.
    static func postcode(_ text: String) async throws -> (CLLocationCoordinate2D, String) {
        struct Response: Decodable {
            struct Result: Decodable {
                let postcode: String
                let latitude: Double?
                let longitude: Double?
            }
            let result: Result
        }
        let clean = text.replacingOccurrences(of: " ", with: "").uppercased()
        guard !clean.isEmpty,
              let encoded = clean.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "https://api.postcodes.io/postcodes/" + encoded) else {
            throw AppError.postcode
        }
        let data: Data
        do { data = try await get(url) } catch AppError.notFound { throw AppError.postcode }
        let r = try JSONDecoder().decode(Response.self, from: data).result
        guard let lat = r.latitude, let lng = r.longitude else { throw AppError.postcode }
        return (CLLocationCoordinate2D(latitude: lat, longitude: lng), r.postcode)
    }
}
