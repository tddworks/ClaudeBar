import Diagnostics
import Foundation

/// `environment` — an environment variable holds the token.
struct EnvironmentReader: CredentialFinding {
    let name: String
    let environment: @Sendable (String) -> String?
    /// The person's login shell, asked only when the app's own environment
    /// lacks the variable; nil for a lookup that doesn't ask for it.
    var loginShell: (@Sendable (String) -> String?)? = nil

    func find() throws -> FoundCredential? {
        let found = environment(name).map(Credential.trimmed).flatMap { $0.isEmpty ? nil : $0 }
            ?? loginShell?(name).map(Credential.trimmed)
        guard let value = found, !value.isEmpty else { return nil }
        return FoundCredential(credential: Credential(["token": value]), save: nil)
    }
}

/// `jsonFile` — a JSON file holds the token and its companions. A refreshed
/// token is written back into the same file, every other field kept and every
/// value keeping its JSON type, because the CLI that owns the file must keep
/// working.
struct JSONFileReader: CredentialFinding {
    let file: JSONFileCredential
    let homeDirectory: URL
    let environment: @Sendable (String) -> String?

    var url: URL {
        URL(fileURLWithPath: Paths.resolve(file.path, homeDirectory: homeDirectory, environment: environment))
    }

    func find() throws -> FoundCredential? {
        guard let document = readDocument() else { return nil }
        if let record = file.record {
            return chosen(record, in: document)
        }
        let values = valuesWithAlternatives(in: document)
        guard values["token"] != nil else { return nil }
        let reader = self
        return FoundCredential(credential: Credential(file.defaults.merging(values) { _, own in own }), save: { reader.write($0) })
    }

    /// The fields, each from the first of its paths that answers.
    private func valuesWithAlternatives(in document: [String: Any]) -> [String: String] {
        var values = CredentialDocument.values(file.fields, in: document)
        for (name, paths) in file.alternatives where values[name] == nil {
            values[name] = paths.lazy.compactMap { CredentialDocument.values([name: $0], in: document)[name] }.first
        }
        return values
    }

    /// The record the rule picks, its values filled out with the defaults; a
    /// refreshed token is written back into that record only.
    private func chosen(_ rule: JSONFileCredential.Record, in document: [String: Any]) -> FoundCredential? {
        let candidates = document.compactMap { key, value -> (key: String, values: [String: String])? in
            guard let record = value as? [String: Any] else { return nil }
            let values = CredentialDocument.values(file.fields, in: record)
            return values["token"] == nil ? nil : (key, values)
        }
        func rank(_ values: [String: String]) -> (Int, Date) {
            let preferred = rule.prefer.map { values[$0] != nil ? 1 : 0 } ?? 0
            let latest = rule.latest.flatMap { values[$0] }.flatMap(Self.instant) ?? .distantFuture
            return (preferred, latest)
        }
        guard let best = candidates.max(by: { rank($0.values) < rank($1.values) }) else { return nil }
        let reader = self
        let key = best.key
        let own = Set(best.values.keys)
        return FoundCredential(credential: Credential(file.defaults.merging(best.values) { _, value in value }),
                               save: { reader.write($0.values.filter { own.contains($0.key) || !reader.file.defaults.keys.contains($0.key) }, into: key) })
    }

    /// An instant written as seconds, or as ISO 8601 with any fraction.
    static func instant(_ text: String) -> Date? {
        if let seconds = Double(text) { return Date(timeIntervalSince1970: seconds) }
        return ISO8601Instant.parse(text)
    }

    private func write(_ values: [String: String], into key: String) {
        guard var document = readDocument(), let record = document[key] as? [String: Any] else { return }
        document[key] = CredentialDocument.updated(record, with: Credential(values), fields: file.fields)
        save(document)
    }

    /// The fields without requiring a token — what a context file supplies.
    func fields() -> [String: String] {
        readDocument().map { CredentialDocument.values(file.fields, in: $0) } ?? [:]
    }

    func write(_ credential: Credential) {
        guard let document = readDocument() else { return }
        // A default the file lacked is never written into it.
        let own = credential.values.filter { file.defaults[$0.key] == nil || $0.value != file.defaults[$0.key] }
        save(CredentialDocument.updated(document, with: Credential(own), fields: file.fields))
    }

    private func save(_ updated: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            AppLog.credentials.info("Saved refreshed credentials to \(file.path)")
        } catch {
            AppLog.credentials.error("Failed to save refreshed credentials to \(file.path): \(error.localizedDescription)")
        }
    }

    private func readDocument() -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// `keychain` — an item in this OS's secret store (`KeychainItems`): the Mac's
/// Keychain, Windows' Credential Manager. A refreshed token is written back
/// as compact JSON, to the item it was read from: the same service and
/// account, "no account" named by the store the same way both times.
struct KeychainReader: CredentialFinding {
    let item: KeychainCredential
    let keychain: any KeychainItems

    func find() throws -> FoundCredential? {
        guard let stored = keychain.password(service: item.service, account: item.account) else {
            AppLog.credentials.error("Keychain item '\(item.service)' wasn't found or couldn't be read")
            return nil
        }
        let password = item.decoded(Credential.trimmed(stored))
        guard !password.isEmpty else { return nil }

        let values: [String: String]
        if let data = Self.decode(password), let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            values = CredentialDocument.values(item.fields, in: document)
        } else if item.fields["token"] == "$" {
            values = ["token": password]
        } else {
            // Shape only — never the payload, which is the token itself.
            AppLog.credentials.error("Keychain item '\(item.service)' did not hold the expected JSON")
            return nil
        }
        guard values["token"] != nil else { return nil }
        let reader = self
        let original = password
        return FoundCredential(credential: Credential(values), save: { reader.write($0, over: original) })
    }

    func write(_ credential: Credential, over password: String) {
        // An encoded item belongs to another tool's library; never rewritten.
        guard item.encoding == nil, let data = Self.decode(password),
              let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let updated = CredentialDocument.updated(document, with: credential, fields: item.fields)
        guard let compact = try? JSONSerialization.data(withJSONObject: updated),
              let payload = String(data: compact, encoding: .utf8) else { return }
        if keychain.save(payload, service: item.service, account: item.account) {
            AppLog.credentials.info("Saved refreshed credentials to Keychain item '\(item.service)'")
        } else {
            AppLog.credentials.error("Failed to save credentials to Keychain item '\(item.service)'")
        }
    }

    /// `security -w` hex-encodes a password with bytes outside printable ASCII
    /// on macOS 26. JSON never starts with a hex digit, so all-hex is the encoded form.
    static func decode(_ password: String) -> Data? {
        if password.count % 2 == 0, !password.isEmpty {
            var bytes = [UInt8]()
            var index = password.startIndex
            var isHex = true
            while index < password.endIndex {
                let next = password.index(index, offsetBy: 2)
                guard let byte = UInt8(password[index..<next], radix: 16) else { isHex = false; break }
                bytes.append(byte)
                index = next
            }
            if isHex { return Data(bytes) }
        }
        return password.data(using: .utf8)
    }
}

/// `firstOf` — the lookup order: the first reader that answers wins.
struct FirstOfReader: CredentialFinding {
    let readers: [any CredentialFinding]

    func find() throws -> FoundCredential? {
        for reader in readers {
            if let found = try reader.find() {
                return found
            }
        }
        return nil
    }
}

/// Reading credential values out of a JSON document, and writing refreshed
/// ones back without changing a value's JSON type.
enum CredentialDocument {
    /// `"$.tokens.id_token#jwt.email"` reads a claim out of a JWT's payload —
    /// display metadata only; the token is not verified. `"$.oauth.scopes#joined"`
    /// reads a list of strings as the one line a refresh asks for (an OAuth
    /// `scope` is space-delimited). A transformed path is never written back.
    static func values(_ fields: [String: String], in document: [String: Any]) -> [String: String] {
        let scope = JSONScope(root: document)
        var values: [String: String] = [:]
        for (name, field) in fields {
            if let value = text(field, in: scope).map(Credential.trimmed), !value.isEmpty {
                values[name] = value
            }
        }
        return values
    }

    /// The transform that reads a list as its space-delimited line.
    static let joined = "#joined"

    private static func text(_ field: String, in scope: JSONScope) -> String? {
        if field.hasSuffix(joined) {
            return list(scope.value(String(field.dropLast(joined.count))))
        }
        let parts = field.components(separatedBy: "#jwt.")
        let value = scope.string(parts[0])
        return parts.count == 2 ? value.flatMap { claim(parts[1], in: $0) } : value
    }

    /// A list of strings as one line, separated by a space.
    static func list(_ value: Any?) -> String? {
        guard let items = value as? [Any] else { return nil }
        let strings = items.compactMap(JSONPath.string)
        return strings.isEmpty ? nil : strings.joined(separator: " ")
    }

    static func claim(_ name: String, in token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return JSONPath.string(JSONPath.walk(claims, JSONPath.components(name)))
    }

    static func updated(_ document: [String: Any], with credential: Credential, fields: [String: String]) -> [String: Any] {
        var updated = document
        let scope = JSONScope(root: document)
        // A transformed path (`#jwt.`, `#joined`) is read-only: the store's own
        // shape is what the CLI that owns it keeps reading.
        for (name, path) in fields where path != "$" && !path.contains("#") {
            guard let value = credential[name] else { continue }
            // A number stays a number: Claude Code reads `expiresAt` as one.
            if scope.value(path) is NSNumber || (scope.value(path) == nil && name == "expiresAt"),
               let number = Double(value) {
                updated = JSONPath.set(NSNumber(value: number), at: path, in: updated)
            } else {
                updated = JSONPath.set(value, at: path, in: updated)
            }
        }
        return updated
    }
}

extension Credential {
    /// A value as a person meant it: no surrounding whitespace or newlines.
    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// `setting` — a key the person gave ClaudeBar, read from its vault.
struct SettingReader: CredentialFinding {
    let name: String
    let providerId: String
    let secrets: (any SecretStore)?

    func find() throws -> FoundCredential? {
        guard let value = secrets?.secret(name, provider: providerId).map(Credential.trimmed), !value.isEmpty else {
            return nil
        }
        return FoundCredential(credential: Credential(["token": value]), save: nil)
    }
}

/// A lookup refined: its `sealed` values opened, the named cookies read out of
/// a Cookie-header token and the `with` values added where nothing was found,
/// then no key unless each `match` pattern matches its value.
struct RefinedReader: CredentialFinding {
    let base: any CredentialFinding
    let refinement: Refinement
    /// Opens `sealed` values; `nil` on a platform with no safeStorage, where a
    /// sealed value fails as `Unavailable` and a clear one still answers.
    let safeStorage: SafeStorage?
    /// The platform's `name`, for that failure.
    let platform: String

    func find() throws -> FoundCredential? {
        guard var found = try base.find() else { return nil }
        if let sealed = refinement.sealed {
            for (name, value) in found.credential.values where value.hasPrefix(sealed.prefix) {
                guard let safeStorage else {
                    throw Unavailable(.lookup, "Opening a sign-in \(sealed.app) keeps sealed", on: platform).error
                }
                found.credential[name] = try safeStorage.open(value, sealed)
            }
        }
        if let header = found.credential["token"] {
            for (name, value) in refinement.cookieValues(in: header) where found.credential[name] == nil {
                found.credential[name] = value
            }
        }
        for (name, value) in refinement.with where found.credential[name] == nil {
            found.credential[name] = value
        }
        // Checked after `with`, so a value a setting added must fit too.
        for (name, pattern) in refinement.match {
            guard let value = found.credential[name], value.range(of: pattern, options: .regularExpression) != nil else {
                AppLog.credentials.info("A key was found but its \(name) isn't one this provider uses; not using it")
                return nil
            }
        }
        return found
    }
}
