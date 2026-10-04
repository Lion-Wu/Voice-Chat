import Foundation
import SQLite3

/// Reads the app's SQLite-backed SwiftData records without materializing corrupt
/// model faults. This adapter only recognizes the storage layout used by this app.
final class RecoveryStoreReader {
    private var database: OpaquePointer?

    init(url: URL) throws {
        let status = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK else {
            let error = databaseError()
            if let database { sqlite3_close(database) }
            database = nil
            throw error
        }
        try query("BEGIN") { _ in }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    /// A failed range is subdivided so a damaged page does not hide later rows.
    /// Unreadable ranges are unknown losses, never reported as an exact row count.
    func scan(entity: String, consume: (RecoveryRow) throws -> Void) throws -> Bool {
        let table = "Z" + entity.uppercased()
        var upperBound: Int64?
        var complete = true
        do {
            try query("SELECT MAX(Z_PK) AS BOUND FROM \(table) NOT INDEXED") { row in
                upperBound = try row.optionalInteger("BOUND")
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            try requireDataError(error)
            complete = false
        }
        if upperBound == nil {
            do {
                try query("SELECT Z_MAX AS BOUND FROM Z_PRIMARYKEY WHERE Z_NAME = '\(entity)'") { row in
                    upperBound = try row.optionalInteger("BOUND")
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                try requireDataError(error)
                complete = false
            }
        }
        guard let upperBound, upperBound >= 0 else {
            try query("SELECT * FROM \(table) NOT INDEXED ORDER BY Z_PK", consume: consume)
            return complete
        }
        func read(_ lower: Int64, _ upper: Int64) throws {
            try Task.checkCancellation()
            guard lower <= upper else { return }
            var next = lower
            do {
                try query("SELECT * FROM \(table) NOT INDEXED WHERE Z_PK BETWEEN \(lower) AND \(upper) ORDER BY Z_PK") { row in
                    let key = try row.integer("Z_PK")
                    try consume(row)
                    next = key == Int64.max ? key : key + 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Only SQLite corruption is a skippable data loss. I/O, storage,
                // permissions, and destination-save failures must abort recovery.
                let error = error as NSError
                guard error.domain == "RecoverySQLite", [SQLITE_CORRUPT, SQLITE_NOTADB].contains(Int32(error.code)) else {
                    throw error
                }
                complete = false
                guard next < upper else { return }
                let midpoint = next + (upper - next) / 2
                try read(next, midpoint)
                try read(midpoint + 1, upper)
            }
        }
        try read(1, upperBound)
        return complete
    }

    private func query(_ sql: String, consume: (RecoveryRow) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        while true {
            try Task.checkCancellation()
            switch sqlite3_step(statement) {
            case SQLITE_DONE: return
            case SQLITE_ROW:
                var values: [String: RecoveryValue] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    let name = String(cString: sqlite3_column_name(statement, index))
                    switch sqlite3_column_type(statement, index) {
                    case SQLITE_INTEGER: values[name] = .integer(sqlite3_column_int64(statement, index))
                    case SQLITE_FLOAT: values[name] = .number(sqlite3_column_double(statement, index))
                    case SQLITE_TEXT:
                        let count = Int(sqlite3_column_bytes(statement, index))
                        if let pointer = sqlite3_column_text(statement, index),
                           let value = String(bytes: UnsafeBufferPointer(start: pointer, count: count), encoding: .utf8) {
                            values[name] = .text(value)
                        } else {
                            values[name] = .invalid
                        }
                    case SQLITE_BLOB:
                        let count = Int(sqlite3_column_bytes(statement, index))
                        if count == 0 { values[name] = .data(Data()) }
                        else if let pointer = sqlite3_column_blob(statement, index) {
                            values[name] = .data(Data(bytes: pointer, count: count))
                        }
                    default: values[name] = .null
                    }
                }
                try consume(RecoveryRow(values: values))
            default: throw databaseError()
            }
        }
    }

    private func requireDataError(_ error: Error) throws {
        let error = error as NSError
        if error.domain == "RecoveryRecord" { return }
        guard error.domain == "RecoverySQLite",
              [SQLITE_ERROR, SQLITE_CORRUPT, SQLITE_NOTADB].contains(Int32(error.code)) else { throw error }
    }

    private func databaseError() -> NSError {
        NSError(domain: "RecoverySQLite", code: Int(sqlite3_errcode(database)), userInfo: [
            NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))
        ])
    }
}

enum RecoveryValue {
    case integer(Int64), number(Double), text(String), data(Data), null, invalid
}

final class RecoveryRow {
    let values: [String: RecoveryValue]
    var hasLoss = false

    init(values: [String: RecoveryValue]) { self.values = values }

    func value<T>(_ field: String, as type: T.Type = T.self) throws -> T {
        let name = "Z" + field.uppercased()
        let result: Any
        switch (values[name], type) {
        case (.text(let value), is String.Type): result = value
        case (.data(let value), is Data.Type): result = value
        case (.data(let value), is UUID.Type) where value.count == 16:
            result = value.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
        case (.integer(let value), is Int.Type):
            guard let integer = Int(exactly: value) else { throw invalid(field) }
            result = integer
        case (.number(let value), is Int.Type):
            guard let integer = Int(exactly: value) else { throw invalid(field) }
            result = integer
        case (.text(let value), is UUID.Type):
            guard let identifier = UUID(uuidString: value) else { throw invalid(field) }
            result = identifier
        case (.integer(let value), is Bool.Type) where value == 0 || value == 1: result = value == 1
        case (.number(let value), is Double.Type) where value.isFinite: result = value
        case (.integer(let value), is Double.Type): result = Double(value)
        case (.number(let value), is Date.Type) where value.isFinite: result = Date(timeIntervalSinceReferenceDate: value)
        case (.integer(let value), is Date.Type): result = Date(timeIntervalSinceReferenceDate: Double(value))
        default: throw invalid(field)
        }
        guard let typed = result as? T else { throw invalid(field) }
        return typed
    }

    /// Recovery overlays readable fields onto an initialized model. An absent
    /// column belongs to an older schema; an invalid stored value is a loss.
    func recover<T>(_ field: String, defaultValue: T) -> T {
        guard values["Z" + field.uppercased()] != nil else { return defaultValue }
        do { return try value(field) }
        catch { hasLoss = true; return defaultValue }
    }

    func recover<T>(_ field: String, defaultValue: T?) -> T? {
        guard let raw = values["Z" + field.uppercased()] else { return defaultValue }
        if case .null = raw { return nil }
        do { return try value(field, as: T.self) }
        catch { hasLoss = true; return defaultValue }
    }

    func integer(_ column: String) throws -> Int64 {
        guard case .integer(let value) = values[column] else { throw invalid(column) }
        return value
    }

    func optionalInteger(_ column: String) throws -> Int64? {
        if case .null = values[column] { return nil }
        return try integer(column)
    }

    func invalid(_ field: String) -> NSError {
        NSError(domain: "RecoveryRecord", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unreadable field: \(field)"])
    }

    func validJSON<T: Codable>(_ value: String?, defaultValue: T) throws -> String {
        if let value, (try? JSONDecoder().decode(T.self, from: Data(value.utf8))) != nil { return value }
        if value != nil { hasLoss = true }
        return String(decoding: try JSONEncoder().encode(defaultValue), as: UTF8.self)
    }

    func validArray<T: Decodable>(_ data: Data?, of type: T.Type) -> Data? {
        guard let data else { return nil }
        guard (try? JSONDecoder().decode([T].self, from: data)) != nil else {
            hasLoss = true
            return nil
        }
        return data
    }

    func readableItems<T: Codable>(_ data: Data?, of type: T.Type) throws -> Data? {
        guard let data else { return nil }
        if (try? JSONDecoder().decode([T].self, from: data)) != nil { return data }
        hasLoss = true
        guard let items = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return nil }
        let readable: [T] = items.compactMap { item in
            guard let encoded = try? JSONSerialization.data(withJSONObject: item, options: [.fragmentsAllowed]) else { return nil }
            return try? JSONDecoder().decode(T.self, from: encoded)
        }
        return try JSONEncoder().encode(readable)
    }
}
