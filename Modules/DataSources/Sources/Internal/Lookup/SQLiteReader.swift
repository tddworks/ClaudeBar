import Quotas
import Foundation

/// `sqlite` — the first row of a read-only query against another app's own
/// database, read through `ReadOnlyQuery`, the one SQLite.
struct SQLiteReader: CredentialFinding {
    let file: SQLiteCredential
    let homeDirectory: URL
    let environment: @Sendable (String) -> String?

    func find() throws -> FoundCredential? {
        let path = Paths.resolve(file.path, homeDirectory: homeDirectory, environment: environment)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let row = try ReadOnlyQuery.rows(at: path, query: file.query, name: file.path.description).first else { return nil }
        let values = CredentialDocument.values(file.fields, in: row)
        guard values["token"] != nil else { return nil }
        return FoundCredential(credential: Credential(values), save: nil)
    }
}

/// `sqlite` as a fetch — the rows of a read-only query against an app's own
/// database are the answer, `[{column: text}]`. Configured while the
/// database is there and one of the call's queries fits it.
struct SQLiteFetcher: Fetching {
    let call: SQLiteCall
    let homeDirectory: URL
    let environment: @Sendable (String) -> String?

    private var path: String {
        Paths.resolve(call.path, homeDirectory: homeDirectory, environment: environment)
    }

    func isReady() -> Bool {
        let path = path
        return FileManager.default.fileExists(atPath: path) && (try? call.query(at: path)) != nil
    }

    func fetch(with credential: Credential?) async throws -> Response {
        let path = path
        guard FileManager.default.fileExists(atPath: path) else {
            throw UsageError.executionFailed("No database at \(call.path)")
        }
        guard let query = try call.query(at: path) else {
            throw UsageError.executionFailed("\(call.path) has none of the tables its queries read")
        }
        let rows = try ReadOnlyQuery.rows(at: path, query: query, name: call.path.description)
        return Response(body: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]))
    }
}

extension SQLiteCall {
    /// The query the database at `path` can answer — its tables read only
    /// when a query requires some — or `nil` when none fits it.
    func query(at path: String) throws -> String? {
        guard needsTables else { return queries[0].query }
        return query(in: try ReadOnlyQuery.tables(at: path, name: self.path.description))
    }
}
