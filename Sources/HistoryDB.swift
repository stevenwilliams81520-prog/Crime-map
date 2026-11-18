import Foundation
import SQLite3
import Compression
import CoreLocation

/// Read-only access to one downloaded force history pack (SQLite).
final class HistoryDB {
    private var db: OpaquePointer?

    init?(path: String) {
        var handle: OpaquePointer?
        if sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            sqlite3_close(handle)
            return nil
        }
        db = handle
    }

    deinit { sqlite3_close(db) }

    func meta() -> [String: String] {
        var out: [String: String] = [:]
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT key, value FROM meta", -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out[text(stmt, 0)] = text(stmt, 1)
        }
        return out
    }

    /// Crimes inside a lat/lng box (values × 100000) between two months (YYYYMM).
    func crimes(minLat: Int, maxLat: Int, minLng: Int, maxLng: Int, fromMonth: Int, toMonth: Int) -> [Crime] {
        let sql = """
        SELECT c.month, k.slug, c.lat, c.lng, s.name, o.name
        FROM crimes c
        JOIN cats k ON k.id = c.cat
        LEFT JOIN streets s ON s.id = c.street
        LEFT JOIN outcomes o ON o.id = c.outcome
        WHERE c.month BETWEEN ?1 AND ?2
          AND c.lat BETWEEN ?3 AND ?4
          AND c.lng BETWEEN ?5 AND ?6
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sqlite3_int64(fromMonth))
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(toMonth))
        sqlite3_bind_int64(stmt, 3, sqlite3_int64(minLat))
        sqlite3_bind_int64(stmt, 4, sqlite3_int64(maxLat))
        sqlite3_bind_int64(stmt, 5, sqlite3_int64(minLng))
        sqlite3_bind_int64(stmt, 6, sqlite3_int64(maxLng))

        var out: [Crime] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let m = Int(sqlite3_column_int64(stmt, 0))
            let outcome = text(stmt, 5)
            out.append(Crime(category: text(stmt, 1),
                             street: text(stmt, 4),
                             month: String(format: "%04d-%02d", m / 100, m % 100),
                             outcome: outcome.isEmpty ? nil : outcome,
                             latitude: Double(sqlite3_column_int64(stmt, 2)) / 1e5,
                             longitude: Double(sqlite3_column_int64(stmt, 3)) / 1e5))
        }
        return out
    }

    private func text(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let p = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: p)
    }
}

/// Raw-DEFLATE file decompression, streamed so big packs don't fill memory.
enum Inflate {
    static func file(_ src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        fm.createFile(atPath: dst.path, contents: nil)
        let output = try FileHandle(forWritingTo: dst)
        defer { try? output.close() }
        let input = try FileHandle(forReadingFrom: src)
        defer { try? input.close() }

        let filter = try OutputFilter(.decompress, using: .zlib) { (data: Data?) in
            if let data = data { try output.write(contentsOf: data) }
        }
        while true {
            let chunk = try input.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            try filter.write(chunk)
        }
        try filter.finalize()
    }
}

/// Download with progress reporting.
enum Downloader {
    static func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            var observation: NSKeyValueObservation?
            let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
                observation?.invalidate()
                if error != nil { cont.resume(throwing: AppError.offline); return }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard let tmp = tmp, code == 200 else { cont.resume(throwing: AppError.server(code)); return }
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    cont.resume(returning: dest)
                } catch {
                    cont.resume(throwing: error)
                }
            }
            observation = task.progress.observe(\.fractionCompleted) { p, _ in
                progress(p.fractionCompleted)
            }
            task.resume()
        }
    }
}

/// Approximate distance in metres (fine for ~1 mile).
func metresBetween(_ a: CLLocationCoordinate2D, _ lat: Double, _ lng: Double) -> Double {
    let x = (lng - a.longitude) * .pi / 180 * cos((a.latitude + lat) / 2 * .pi / 180)
    let y = (lat - a.latitude) * .pi / 180
    return sqrt(x * x + y * y) * 6_371_000
}
