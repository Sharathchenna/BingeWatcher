import Foundation
import SQLite3

struct NeighborCandidate: Identifiable, Equatable {
    let sourceTMDBID: Int
    let neighborTMDBID: Int
    let rank: Int
    let similarity: Float

    var id: String {
        "\(sourceTMDBID)-\(neighborTMDBID)-\(rank)"
    }
}

final class CollabLookup {
    private let databasePath: String?

    init(databaseURL: URL? = Bundle.main.url(forResource: "neighbors", withExtension: "sqlite")) {
        self.databasePath = databaseURL?.path
    }

    func latentFactors(forTMDBID tmdbID: Int) -> [Float] {
        guard let databasePath else {
            return Array(repeating: .zero, count: 47)
        }

        let sql = "SELECT factor_index, factor_value FROM movie_factors WHERE tmdb_id = ? ORDER BY factor_index ASC LIMIT 47;"
        var output = Array(repeating: Float.zero, count: 47)

        do {
            try withDatabase(at: databasePath) { database in
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw SQLiteLookupError.prepare(message: currentErrorMessage(for: database))
                }
                defer { sqlite3_finalize(statement) }

                sqlite3_bind_int(statement, 1, Int32(tmdbID))

                while sqlite3_step(statement) == SQLITE_ROW {
                    let factorIndex = Int(sqlite3_column_int(statement, 0))
                    guard output.indices.contains(factorIndex) else {
                        continue
                    }
                    output[factorIndex] = Float(sqlite3_column_double(statement, 1))
                }
            }
        } catch {
            return Array(repeating: .zero, count: 47)
        }

        return output
    }

    func nearestNeighbors(forTMDBID tmdbID: Int, limit: Int = 50) -> [NeighborCandidate] {
        guard let databasePath else {
            return []
        }

        let sql = "SELECT source_tmdb_id, neighbor_tmdb_id, neighbor_rank, similarity FROM movie_neighbors WHERE source_tmdb_id = ? ORDER BY neighbor_rank ASC LIMIT ?;"
        var candidates: [NeighborCandidate] = []

        do {
            try withDatabase(at: databasePath) { database in
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw SQLiteLookupError.prepare(message: currentErrorMessage(for: database))
                }
                defer { sqlite3_finalize(statement) }

                sqlite3_bind_int(statement, 1, Int32(tmdbID))
                sqlite3_bind_int(statement, 2, Int32(limit))

                while sqlite3_step(statement) == SQLITE_ROW {
                    candidates.append(
                        NeighborCandidate(
                            sourceTMDBID: Int(sqlite3_column_int(statement, 0)),
                            neighborTMDBID: Int(sqlite3_column_int(statement, 1)),
                            rank: Int(sqlite3_column_int(statement, 2)),
                            similarity: Float(sqlite3_column_double(statement, 3))
                        )
                    )
                }
            }
        } catch {
            return []
        }

        return candidates
    }

    private func withDatabase(at path: String, operation: (OpaquePointer?) throws -> Void) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            defer { sqlite3_close(database) }
            throw SQLiteLookupError.open(message: currentErrorMessage(for: database))
        }
        defer { sqlite3_close(database) }
        try operation(database)
    }

    private func currentErrorMessage(for database: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }
}

enum SQLiteLookupError: Error {
    case open(message: String)
    case prepare(message: String)
}
