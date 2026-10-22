import Foundation
import Testing
@testable import DataSources

/// Which of a provider's settings a data source reads — so Settings shows
/// exactly the fields that change what it does (#602).
@Suite
struct DataSourceSettingsTests {
    private func source(credential: CredentialLookup? = nil, fetch: Fetch) -> DataSourceDefinition {
        DataSourceDefinition(kind: "api", credential: credential, fetch: fetch, mapping: .json(JSONMapping(quotas: [])))
    }

    private let plainRequest = Fetch.http(HTTPRequest(url: "https://api.acme.example/usage"))

    @Test func `should read the key its credential names, however the lookup is wrapped`() {
        let api = source(credential: .firstOf([.environment("ACME_API_KEY"), .setting("apiKey")]), fetch: plainRequest)

        #expect(api.settingsRead.contains("apiKey"))
    }

    @Test func `should read a setting its request fills in`() {
        let api = source(fetch: .http(HTTPRequest(url: "https://{{setting.region}}.acme.example/usage")))

        #expect(api.settingsRead == ["region"])
    }

    @Test func `should read a choice's value as it is written, for its setting to claim`() {
        let api = source(fetch: .http(HTTPRequest(url: "https://{{setting.region.console}}/usage")))

        #expect(api.settingsRead == ["region.console"])
    }

    @Test func `should read a key a script is handed as a secret`() {
        let script = source(fetch: .script(ScriptCall(run: "./probe.sh", folder: "/tmp/acme",
                                                       secrets: ["CLAUDEBAR_API_KEY": "apiKey"])))

        #expect(script.settingsRead == ["apiKey"])
    }

    @Test func `should not read a setting it never names`() {
        let script = source(fetch: .script(ScriptCall(run: "./probe.sh", folder: "/tmp/acme",
                                                       secrets: ["CLAUDEBAR_API_KEY": "apiKey"])))

        #expect(!script.settingsRead.contains("region"))
        #expect(!script.settingsRead.contains("api"))
    }
}
