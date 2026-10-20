#if DEBUG
import Foundation
import GRDB

/// Bounded local visual-review copy. Source reads are transactional; saved values are never recomputed.
enum OwnerDataReviewSlice {
    struct Result {
        let counts: [String: Int]
        let rawSince: Int
        let rawThrough: Int
    }
    static func create(from source: any DatabaseReader, at target: URL, calendar: Calendar = .current) throws -> Result {
        // Exclusive creation prevents replacement of any existing database, including the owner's store.
        try Data().write(to: target, options: [.withoutOverwriting])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        let destination = try DatabaseQueue(path: target.path)
        return try source.read { original in
            guard let latest = try Int.fetchOne(original, sql: "SELECT MAX(ts) FROM hrSample") else {
                throw CocoaError(.fileReadUnknown)
            }
            let midnight = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(latest)))
            guard let start = calendar.date(byAdding: .day, value: -2, to: midnight) else {
                throw CocoaError(.fileReadUnknown)
            }
            let floor = Int(start.timeIntervalSince1970)
            let completeTables: Set<String> = ["grdb_migrations", "device", "pairedDevice", "dailyMetric",
                "metricSeries", "scoreInputProvenance", "dayOwnership", "appleDaily", "appleStepHour",
                "sleepSession", "workout"]
            let recentTables: Set<String> = ["hrSample", "rrInterval", "stepSample", "battery"]
            let schema = try Row.fetchAll(original, sql: "SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 ELSE 2 END")
            let tables = schema.filter { ($0["type"] as String) == "table" }
            var counts: [String: Int] = [:]
            try destination.write { copy in
                for entry in tables {
                    let sql: String = entry["sql"]
                    try copy.execute(sql: sql)
                }
                for entry in tables {
                    let name: String = entry["name"]
                    guard completeTables.contains(name) || recentTables.contains(name) else { continue }
                    let identifier = "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                    let query = "SELECT * FROM " + identifier + (recentTables.contains(name) ? " WHERE ts >= ? AND ts <= ?" : "")
                    let args: StatementArguments = recentTables.contains(name) ? [floor, latest] : []
                    let count = try Int.fetchOne(original, sql: "SELECT COUNT(*) FROM (" + query + ")", arguments: args) ?? 0
                    // Fail rather than silently sampling, truncating, or exporting unbounded raw history.
                    guard count <= 500_000 else { throw CocoaError(.fileReadTooLarge) }
                    let cursor = try Row.fetchCursor(original, sql: query, arguments: args)
                    var statement: Statement?
                    var copied = 0
                    while let row = try cursor.next() {
                        if statement == nil {
                            statement = try copy.makeStatement(sql: "INSERT INTO " + identifier + " VALUES (" + Array(repeating: "?", count: row.count).joined(separator: ",") + ")")
                        }
                        try statement?.execute(arguments: StatementArguments(row.map { $0.1 }))
                        copied += 1
                    }
                    guard copied == count else { throw CocoaError(.fileReadCorruptFile) }
                    counts[name] = copied
                }
                for entry in schema where (entry["type"] as String) != "table" {
                    let sql: String = entry["sql"]
                    try copy.execute(sql: sql)
                }
                guard try String.fetchOne(copy, sql: "PRAGMA quick_check") == "ok" else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
            return Result(counts: counts, rawSince: floor, rawThrough: latest)
        }
    }
}
#endif
