import ClaudeBarKit
import Foundation

// The face of what pages switch on and count with: Swift enums for Kotlin's sealed classes,
// `Int` and `Bool` for Kotlin's boxed numbers, and Swift names for companions — so no view
// names `onEnum`, `KotlinLong` or `companion` (MODULAR_DESIGN §5, rule 4).

// MARK: - Shapes to switch on

extension Setting {
    /// What a setting asks for, for `switch`.
    public enum Shape {
        case text, secret, path
        case choice([Setting.Option])
    }

    public var shape: Shape {
        switch onEnum(of: kind) {
        case .text: .text
        case .secret: .secret
        case .path: .path
        case .choice(let choice): .choice(choice.options)
        }
    }
}

extension NewSessions.State {
    /// What *In use* says under a product's chips, for `switch`.
    public enum Shape {
        case waitingForSetup
        case worthSwitching(from: Account, to: Account)
        case using(Account)
    }

    public var shape: Shape {
        switch onEnum(of: self) {
        case .waitingForSetup: .waitingForSetup
        case .worthSwitching(let worth): .worthSwitching(from: worth.from, to: worth.to)
        case .using(let using): .using(using.login)
        }
    }
}

extension RankCard {
    /// Where the rank is on the board, for `switch`.
    public enum PlacementShape {
        case top(percent: Int)
        case rank(of: Int)
        case topHundred
        case none
    }

    public var placementShape: PlacementShape {
        switch onEnum(of: placement) {
        case .top(let top): .top(percent: Int(top.percent))
        case .rank(let rank): .rank(of: Int(rank.of))
        case .topHundred: .topHundred
        case .none: .none
        }
    }
}

extension DraftPreview {
    /// What a draft would show for an answer, for `switch`.
    public enum Shape {
        case usage(UsageSnapshot)
        case incomplete(String)
        case failed(DataSourceError)
    }

    public var shape: Shape {
        switch onEnum(of: self) {
        case .usage(let preview): .usage(preview.usage)
        case .incomplete(let missing): .incomplete(missing.reason)
        case .failed(let failed): .failed(failed.error)
        }
    }
}

// MARK: - Numbers as Swift counts them

extension SwitchWhenLow {
    /// The percentage *Switch when low* moves at.
    public var belowPercent: Int {
        get { Int(below) }
        set { below = Int32(newValue) }
    }
}

extension Standing {
    /// Tokens per provider, for the mix bar.
    public var tokensByProvider: [String: Int] { byProvider.mapValues { Int($0.int64Value) } }
}

extension Account {
    /// The lowest quota's percentage left; nil before any usage.
    public var leftPercent: Double? { percentLeft?.doubleValue }
}

extension Accounts {
    /// Moves a login to `index` in the person's order.
    public func move(_ account: Account, to index: Int) {
        move(account: account, index: Int32(index))
    }
}

extension Providers {
    /// Moves a provider `offset` places up (negative) or down the lineup.
    public func move(_ id: String, by offset: Int) {
        move(id: id, offset: Int32(offset))
    }
}

extension QuotaMonitor {
    /// ⌘1–⌘9: the tab at `position`, counted from one.
    public func selectTab(at position: Int) {
        selectProvider(atPosition: Int32(position))
    }
}

extension QuotaAlerts {
    public func remove(percent: Int) {
        remove(percent: Int32(percent))
    }
}

extension Provider {
    /// Whether a refresh of `account` could run now — its key is found, its CLI is there.
    public func canRefresh(_ account: Account) async -> Bool {
        (try? await isAvailable(account: account))?.boolValue ?? false
    }
}

extension NotificationAlerter {
    /// Asks to send alerts; true when the person allows them.
    public func askPermission() async -> Bool {
        (try? await requestPermission())?.boolValue ?? false
    }
}

// MARK: - Companions by Swift names

extension GuestPass {
    /// A pass to share, its count unknown.
    public static func sharing(_ referralURL: String) -> GuestPass {
        companion.of(passesRemaining: nil, referralURL: referralURL)
    }
}

extension ResponseFields {
    /// The values of an answer, sorted by path; none before anything came back.
    public static func of(_ response: Response?) -> ResponseFields {
        response.map { companion.of(response: $0) } ?? companion.empty
    }

    /// A text answer's non-empty lines — what a CLI printed.
    public static func lines(of response: Response) -> [String] {
        companion.lines(response: response)
    }
}

extension Response {
    /// An answer with a status and a body, as a test or a preview makes one.
    public convenience init(status: Int, body: Data = Data()) {
        let bytes = KotlinByteArray(size: Int32(body.count))
        for (index, byte) in body.enumerated() { bytes.set(index: Int32(index), value: Int8(bitPattern: byte)) }
        self.init(status: KotlinInt(value: Int32(status)), headers: [:], body: bytes)
    }
}

extension NotifyDeviceLink {
    /// A device id and token read from whatever the person pasted — a URL, a pair — or nil.
    public static func pasted(_ text: String) -> NotifyDeviceLink? { companion.fromPastedText(pastedText: text) }

    /// The device id in pasted text, when a token isn't there.
    public static func deviceId(inPastedText text: String) -> String? { companion.deviceIdInPastedText(text: text) }

    public static func isValidDeviceId(_ value: String) -> Bool { companion.isValidDeviceId(value: value) }

    public static func link(deviceId: String, token: String) -> NotifyDeviceLink? { companion.of(deviceId: deviceId, token: token) }
}

extension NotifyDeviceKind {
    public static func of(deviceId: String) -> NotifyDeviceKind { companion.of(deviceId: deviceId) }
}

extension ClaudeBarCore {
    /// The kit over `home`, its built-in providers read from `definitions`.
    public static func start(definitions: String, home: String) -> ClaudeBarCore {
        companion.start(definitions: definitions, home: home)
    }
}
