import Testing
import Foundation
@testable import Domain

@Suite
struct NotifyDeviceLinkTests {

    // MARK: - Pasted URLs

    @Test
    func `a notification URL parses into an id and a token`() {
        // Given the URL the Notify! app puts on the clipboard
        let pasted = "https://push.getnotifyapp.com/notify/ABCD1234?token=s3cr3t-t0k3n"

        // When
        let link = NotifyDeviceLink(pastedText: pasted)

        // Then
        #expect(link?.deviceId == "ABCD1234")
        #expect(link?.token == "s3cr3t-t0k3n")
    }

    @Test
    func `the live activity URL form parses`() {
        let link = NotifyDeviceLink(pastedText: "https://push.getnotifyapp.com/live-activity/ABCD1234?token=s3cr3t")

        #expect(link?.deviceId == "ABCD1234")
        #expect(link?.token == "s3cr3t")
    }

    @Test
    func `the widgets URL form parses`() {
        let link = NotifyDeviceLink(pastedText: "https://push.getnotifyapp.com/widgets/ABCD1234?token=s3cr3t")

        #expect(link?.deviceId == "ABCD1234")
        #expect(link?.token == "s3cr3t")
    }

    @Test
    func `a URL with no token fails`() {
        // The gateway will not talk to us without the secret, so a URL that
        // lost its query is worth rejecting in the settings pane rather than
        // discovering as a 403 later.
        #expect(NotifyDeviceLink(pastedText: "https://push.getnotifyapp.com/notify/ABCD1234") == nil)
    }

    // MARK: - Pasted pairs

    @Test
    func `an id and token separated by a space parse`() {
        let link = NotifyDeviceLink(pastedText: "ABCD1234 s3cr3t")

        #expect(link?.deviceId == "ABCD1234")
        #expect(link?.token == "s3cr3t")
    }

    @Test
    func `an id and token separated by a comma parse`() {
        let link = NotifyDeviceLink(pastedText: "ABCD1234,s3cr3t")

        #expect(link?.deviceId == "ABCD1234")
        #expect(link?.token == "s3cr3t")
    }

    @Test
    func `an id and token separated by a colon parse`() {
        let link = NotifyDeviceLink(pastedText: "ABCD1234:s3cr3t")

        #expect(link?.deviceId == "ABCD1234")
        #expect(link?.token == "s3cr3t")
    }

    // MARK: - Rejected input

    @Test
    func `an id that is too short fails`() {
        #expect(NotifyDeviceLink(pastedText: "ABC1234 s3cr3t") == nil)
    }

    @Test
    func `an id that is too long fails`() {
        #expect(NotifyDeviceLink(pastedText: "A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q s3cr3t") == nil)
    }

    @Test
    func `an id with non alphanumeric characters fails`() {
        #expect(NotifyDeviceLink(pastedText: "ABCD_1234 s3cr3t") == nil)
    }

    @Test
    func `an empty string fails`() {
        #expect(NotifyDeviceLink(pastedText: "") == nil)
        #expect(NotifyDeviceLink(pastedText: "   \n ") == nil)
    }

    // MARK: - Trimming

    @Test
    func `whitespace around the pasted text is trimmed`() {
        // A copy out of a chat message or an email arrives with a newline on
        // the end more often than not.
        let link = NotifyDeviceLink(pastedText: "  https://push.getnotifyapp.com/notify/ABCD1234?token=s3cr3t\n")

        #expect(link?.deviceId == "ABCD1234")
        #expect(link?.token == "s3cr3t")
    }

    @Test
    func `whitespace around a typed id and token is trimmed`() {
        let link = NotifyDeviceLink(deviceId: "  ABCD1234  ", token: "  s3cr3t  ")

        #expect(link?.deviceId == "ABCD1234")
        #expect(link?.token == "s3cr3t")
    }

    // MARK: - Device id shape

    @Test
    func `isValidDeviceId accepts the id lengths the gateway issues`() {
        // Eight for an iPhone, "WB" plus fourteen for the web, and the
        // thirty two character ceiling.
        #expect(NotifyDeviceLink.isValidDeviceId("ABCD1234"))
        #expect(NotifyDeviceLink.isValidDeviceId("WBabcdef12345678"))
        #expect(NotifyDeviceLink.isValidDeviceId("A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6"))
    }

    @Test
    func `isValidDeviceId rejects an id outside the eight to thirty two range`() {
        #expect(!NotifyDeviceLink.isValidDeviceId("ABC1234"))
        #expect(!NotifyDeviceLink.isValidDeviceId("A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q"))
    }

    // MARK: - Half a link

    @Test
    func `a URL with no token still names its device`() {
        // The gateway's own /link response hands back a notification_url with
        // the token deliberately stripped, so this shape is real rather than a
        // typo, and half an answer is still worth filling into a field.
        #expect(
            NotifyDeviceLink.deviceId(inPastedText: "https://push.getnotifyapp.com/notify/ABC12345")
                == "ABC12345"
        )
    }

    @Test
    func `a bare device id is its own answer`() {
        #expect(NotifyDeviceLink.deviceId(inPastedText: "  ABC12345  ") == "ABC12345")
    }

    @Test
    func `an id and token pair reports just the id`() {
        #expect(NotifyDeviceLink.deviceId(inPastedText: "ABC12345 sekret-token") == "ABC12345")
    }

    @Test
    func `text naming no usable device id reports nothing`() {
        #expect(NotifyDeviceLink.deviceId(inPastedText: "") == nil)
        #expect(NotifyDeviceLink.deviceId(inPastedText: "not a link") == nil)
        #expect(NotifyDeviceLink.deviceId(inPastedText: "https://push.getnotifyapp.com/notify/short") == nil)
    }

    // MARK: - Device Kind

    @Test
    func `a GRP id with five characters is a group`() {
        // Given the group namespace, which is eight characters in total, exactly
        // the length of a legacy device id
        // When & Then: the prefix is the only thing that separates the two, and
        // it is what the gateway's own router looks at first
        #expect(NotifyDeviceKind.kind(ofDeviceId: "GRPA1B2C") == .group)
    }

    @Test
    func `a WB id with fourteen characters is a browser`() {
        #expect(NotifyDeviceKind.kind(ofDeviceId: "WB9K4TR2ZQ7M1XPD") == .web)
    }

    @Test
    func `an MC id with fourteen characters is a Mac`() {
        #expect(NotifyDeviceKind.kind(ofDeviceId: "MC3F7Q2ZKM4H2QZ1") == .mac)
    }

    @Test
    func `an IO id with fourteen characters is an app device`() {
        // The newer iOS namespace. Unlike the legacy format it is unambiguous:
        // no Mac listener has ever minted one, so a tile can be started on it
        // without the gateway needing to settle the question.
        #expect(NotifyDeviceKind.kind(ofDeviceId: "IO7Q2ZKM4H2QZ1XY") == .appDevice)
        #expect(NotifyDeviceKind.kind(ofDeviceId: "IO7Q2ZKM4H2QZ1XY").supportsLiveActivity)
        #expect(NotifyDeviceKind.kind(ofDeviceId: "IO7Q2ZKM4H2QZ1XY").supportsWidget)
    }

    @Test
    func `an app device id longer than eight characters still carries both surfaces`() {
        // App device ids are not one fixed shape and more formats are coming, so
        // the rule is which namespaces CANNOT show a surface, never which lengths
        // may. A twelve character id nobody has taught this code about is a
        // device to publish to, not a device to refuse.
        let kind = NotifyDeviceKind.kind(ofDeviceId: "A1B2C3D4E5F6")

        #expect(kind.supportsLiveActivity)
        #expect(kind.supportsWidget)
        #expect(kind.liveActivityUnsupportedReason == nil)
        #expect(kind.widgetUnsupportedReason == nil)
    }

    @Test
    func `a bare eight character id is an app device`() {
        #expect(NotifyDeviceKind.kind(ofDeviceId: "ABCD1234") == .appDevice)
    }

    @Test
    func `a lowercase eight character id is still an app device`() {
        // iOS mints the legacy format in uppercase, but older Mac listeners
        // minted it mixed case, so lowercase ids are real ids somebody can paste
        // today and reading one as a stranger would refuse a working phone.
        #expect(NotifyDeviceKind.kind(ofDeviceId: "abcd1234") == .appDevice)
        #expect(NotifyDeviceKind.kind(ofDeviceId: "AbCd1234") == .appDevice)
    }

    @Test
    func `a prefix with the wrong number of characters after it is not that namespace`() {
        // The length is part of the grammar rather than decoration. "WB" plus
        // thirteen and "GRP" plus six sit in no namespace at all, so they land on
        // unrecognized and the gateway gets the last word, which is the only
        // honest answer available locally.
        #expect(NotifyDeviceKind.kind(ofDeviceId: "WB9K4TR2ZQ7M1XP") == .unrecognized)
        #expect(NotifyDeviceKind.kind(ofDeviceId: "GRPA1B2C3") == .unrecognized)
    }

    @Test
    func `a WB prefix on an eight character id is an ordinary app device`() {
        // Eight characters is the legacy grammar whatever those characters spell,
        // so this is a phone whose id merely begins with two familiar letters.
        #expect(NotifyDeviceKind.kind(ofDeviceId: "WBA1B2C3") == .appDevice)
    }

    @Test
    func `a prefix followed by lowercase characters is not that namespace`() {
        // "GRP", "WB" and "MC" are uppercase only namespaces, so a lowercase tail
        // means some other kind of id: sixteen characters belong to no namespace,
        // and eight are the legacy device grammar again.
        #expect(NotifyDeviceKind.kind(ofDeviceId: "WBabcdef12345678") == .unrecognized)
        #expect(NotifyDeviceKind.kind(ofDeviceId: "MCabcdef12345678") == .unrecognized)
        #expect(NotifyDeviceKind.kind(ofDeviceId: "GRPabcde") == .appDevice)
    }

    @Test
    func `a Mac and a browser can keep a widget but cannot show a Live Activity`() {
        // The two surfaces are gated differently and only one of them is gated by
        // the namespace. The gateway refuses a Live Activity start for a Mac or a
        // browser outright, naming them, but it is equally explicit that widgets
        // carry no device type gate and that legacy, WB and MC ids can all own
        // one. Refusing a widget here would be ClaudeBar inventing a rule the
        // service does not have.
        for kind in [NotifyDeviceKind.mac, .web] {
            #expect(kind.supportsLiveActivity == false)
            #expect(kind.supportsWidget)
            #expect(kind.supportsAnySurface)
        }
    }

    @Test
    func `a group carries neither surface, being no device at all`() {
        // A group is a fan-out target. It has members, and no Lock Screen and no
        // widget list of its own for anything to sit in.
        #expect(NotifyDeviceKind.group.supportsLiveActivity == false)
        #expect(NotifyDeviceKind.group.supportsWidget == false)
        #expect(NotifyDeviceKind.group.supportsAnySurface == false)
    }

    @Test
    func `an app device carries both Lock Screen surfaces`() {
        #expect(NotifyDeviceKind.appDevice.supportsLiveActivity)
        #expect(NotifyDeviceKind.appDevice.supportsWidget)
        #expect(NotifyDeviceKind.appDevice.supportsAnySurface)
    }

    @Test
    func `an app device, a Mac and a browser can all keep a Home Screen widget`() {
        // The gateway is explicit that screen widgets carry no device type gate
        // at all and that legacy, IO, WB and MC ids can each own one. Only the
        // iOS app draws them, but which device draws what is Notify!'s business
        // rather than a rule for ClaudeBar to invent on the user's behalf.
        for kind in [NotifyDeviceKind.appDevice, .mac, .web, .unrecognized] {
            #expect(kind.supportsScreenWidget)
            #expect(kind.screenWidgetUnsupportedReason == nil)
        }
    }

    @Test
    func `a group can keep no Home Screen widget either`() {
        // The one exception, and for the reason it keeps no Lock Screen widget:
        // a group is a fan-out target with no screen of its own for a tile to
        // stay on.
        #expect(NotifyDeviceKind.group.supportsScreenWidget == false)
        #expect(NotifyDeviceKind.group.screenWidgetUnsupportedReason != nil)
    }

    @Test
    func `an id from a namespace nobody knows yet is allowed through`() {
        // Refusing an unknown shape would break the day Notify! mints a new
        // namespace, and ClaudeBar would be wrong about a device it has never
        // heard of. Letting it through costs one request and lets the gateway,
        // the only party that can actually tell, decide.
        let kind = NotifyDeviceKind.kind(ofDeviceId: "XY9K4TR2ZQ7M1XPD")

        #expect(kind == .unrecognized)
        #expect(kind.supportsLiveActivity)
        #expect(kind.supportsWidget)
    }

    @Test
    func `each reason is present exactly when its own surface is unavailable`() {
        // The pane shows these sentences in place of a control, so a kind that
        // works with a reason attached would explain away a switch that is fine,
        // and one that does not work without a reason would leave a dead control
        // with no account of itself.
        for kind in NotifyDeviceKind.allCases {
            #expect((kind.liveActivityUnsupportedReason == nil) == kind.supportsLiveActivity)
            #expect((kind.widgetUnsupportedReason == nil) == kind.supportsWidget)
        }
    }

    @Test
    func `a Mac is told its widget still works`() {
        // The whole point of gating the two surfaces separately: a Mac user who
        // reads only that a Live Activity is unavailable would reasonably give up
        // on the feature, when half of it works for them.
        let reason = NotifyDeviceKind.mac.liveActivityUnsupportedReason

        #expect(reason?.contains("iPhone") == true)
        #expect(reason?.contains("widget") == true)
    }

    @Test
    func `a group link parses and reports itself as a group`() {
        // Given the URL Notify! hands out for a group
        let pasted = "https://push.getnotifyapp.com/notify/GRPA1B2C?token=s3cr3t"

        // When
        let link = NotifyDeviceLink(pastedText: pasted)

        // Then: refusing to parse it would have the pane say "that is not a
        // link", which is untrue and no help. It is a perfectly good link that
        // simply owns no Lock Screen, and that is the thing worth saying.
        #expect(link?.deviceId == "GRPA1B2C")
        #expect(link?.kind == .group)
        #expect(link?.supportsLiveActivity == false)
        #expect(link?.supportsWidget == false)
    }

    @Test
    func `a Mac link carries a widget but not a Live Activity`() {
        // A Mac link is a real link and half the feature works on it. Only the
        // Live Activity is refused, and by the gateway rather than by ClaudeBar:
        // it names a Mac of either generation and a web push browser as devices
        // that cannot show one at all.
        let link = NotifyDeviceLink(deviceId: "MC3F7Q2ZKM4H2QZ1", token: "s3cr3t")

        #expect(link?.kind == .mac)
        #expect(link?.supportsLiveActivity == false)
        #expect(link?.supportsWidget == true)
    }

    // MARK: - Device description

    @Test
    func `a device with a platform describes itself with the platform in parentheses`() {
        let info = NotifyDeviceInfo(deviceId: "ABCD1234", name: "Apollo", platform: "iOS")

        #expect(info.displayDescription == "Apollo (iOS)")
    }

    @Test
    func `a device with no platform describes itself by name alone`() {
        #expect(NotifyDeviceInfo(deviceId: "ABCD1234", name: "Apollo").displayDescription == "Apollo")
        #expect(NotifyDeviceInfo(deviceId: "ABCD1234", name: "Apollo", platform: "").displayDescription == "Apollo")
    }
}
