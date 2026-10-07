import Foundation
import Kit

/// What *Add Provider* has typed so far — page state, a value SwiftUI binds each field to.
/// The kit's `ProviderDraft` is made from it only when it is tested, previewed or saved.
struct ProviderDraftForm: Equatable {
    enum Start: Equatable {
        case api, cli, file
        case copy(ProviderDefinition)
    }

    enum KeySource: Equatable {
        case apiKey
        case environment(String)
    }

    enum SentAs: Equatable {
        case bearer
        case header(String)
    }

    enum Measure: Equatable {
        case percentUsed, percentLeft
        case money(currency: String)
    }

    enum ResetsFormat: Equatable { case iso8601, epochSeconds, secondsFromNow }

    let start: Start

    // Connect
    var url = ""
    var command = ""
    var path = ""
    var key: KeySource? = .apiKey
    var sentAs: SentAs = .bearer

    // Map fields
    var measure: Measure = .percentUsed
    var used: String?
    var remaining: String?
    var limit: String?
    var resets: String?
    var resetsFormat: ResetsFormat = .iso8601
    var textLabel: String?
    var quotaName = "Usage"

    // Look
    var name: String
    var symbol: String?
    var color: ProviderLook.Shades?
    var dashboard = ""

    init(start: Start) {
        self.start = start
        if case .copy(let source) = start { name = source.profile.name } else { name = "" }
    }

    /// The kit's draft, holding everything typed here.
    var draft: ProviderDraft {
        let kitStart: ProviderDraft.Start = switch start {
        case .api: ProviderDraft.StartApi.shared
        case .cli: ProviderDraft.StartCli.shared
        case .file: ProviderDraft.StartFile.shared
        case .copy(let source): ProviderDraft.StartCopy(source: source)
        }
        let draft = ProviderDraft(start: kitStart)
        draft.url = url
        draft.command = command
        draft.path = path
        draft.key = switch key {
        case .apiKey: ProviderDraft.KeySourceApiKey.shared
        case .environment(let variable): ProviderDraft.KeySourceEnvironment(variable: variable)
        case nil: nil
        }
        draft.sentAs = switch sentAs {
        case .bearer: ProviderDraft.SentAsBearer.shared
        case .header(let name): ProviderDraft.SentAsHeader(name: name)
        }
        draft.measure = switch measure {
        case .percentUsed: ProviderDraft.MeasurePercentUsed.shared
        case .percentLeft: ProviderDraft.MeasurePercentLeft.shared
        case .money(let currency): ProviderDraft.MeasureMoney(currency: currency)
        }
        draft.used = used
        draft.remaining = remaining
        draft.limit = limit
        draft.resets = resets
        draft.resetsFormat = switch resetsFormat {
        case .iso8601: .iso8601
        case .epochSeconds: .epochSeconds
        case .secondsFromNow: .secondsFromNow
        }
        draft.textLabel = textLabel
        draft.quotaName = quotaName
        draft.name = name
        draft.symbol = symbol
        draft.color = color
        draft.dashboard = dashboard
        return draft
    }
}
