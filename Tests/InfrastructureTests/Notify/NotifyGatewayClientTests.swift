import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct NotifyGatewayClientTests {

    // MARK: - Fixtures

    static let host = NotifyGatewayClient.defaultHost
    static let deviceId = "ABC12345"
    static let token = "sekret-token-42"
    static let activityId = "LA7Q2ZKM"
    static let widgetId = "WG4H2QZ1"
    static let screenWidgetId = "SW8N3PQ2"

    // The three ids that name something with no Lock Screen of its own: a push
    // capable Mac listener, a web push browser, and a notification group.
    static let macDeviceId = "MC3F7Q2ZKM4H2QZ1"
    static let webDeviceId = "WB9K4TR2ZQ7M1XPD"
    static let groupDeviceId = "GRPA1B2C"

    static let startResponse = """
    {
      "success": true,
      "activityId": "LA7Q2ZKM",
      "expiresAt": "2026-09-03T18:00:00Z"
    }
    """

    static let widgetResponse = """
    {
      "widgetId": "WG4H2QZ1",
      "content": { "title": "ClaudeBar" },
      "createdAt": "2026-09-03T09:00:00Z",
      "updatedAt": "2026-09-03T09:00:00Z",
      "updateUrl": "https://push.getnotifyapp.com/widgets/WG4H2QZ1"
    }
    """

    /// The `ScreenWidget` object. `staleAt` is the phone's freshness deadline and rides along on
    /// every write, but ClaudeBar has no decision to make about it, so only the id is read.
    static let screenWidgetResponse = """
    {
      "screenWidgetId": "SW8N3PQ2",
      "content": { "title": "ClaudeBar" },
      "staleAt": 1772539200,
      "createdAt": "2026-09-03T09:00:00Z",
      "updatedAt": "2026-09-03T09:00:00Z",
      "updateUrl": "https://push.getnotifyapp.com/screenwidgets/SW8N3PQ2"
    }
    """

    static let linkResponse = """
    {
      "success": true,
      "type": "device",
      "id": "ABC12345",
      "name": "Apollo",
      "notification_url": "https://push.getnotifyapp.com/notify/ABC12345?token=sekret-token-42",
      "last_active": "2026-09-03T08:59:00Z",
      "platform": "iOS",
      "os_version": "26.0",
      "app_version": "3.1.0",
      "message": "ok"
    }
    """

    // MARK: - Domain Factories

    // The Notify! value types are all failable, because a title the gateway would reject must not
    // become a tile at all. Every fixture below sits well inside the limits, so a nil here would
    // mean the limits themselves moved rather than the test being wrong, and `#require` says that
    // once instead of a force unwrap at each call site.

    private func makeLink(deviceId: String = Self.deviceId, token: String = Self.token) throws -> NotifyDeviceLink {
        try #require(NotifyDeviceLink(deviceId: deviceId, token: token))
    }

    private func makeMetric(
        label: String,
        value: String,
        unit: String? = nil,
        tintHex: String? = nil
    ) throws -> NotifyMetric {
        try #require(NotifyMetric(label: label, value: value, unit: unit, tintHex: tintHex))
    }

    /// A tile with every field ClaudeBar drives populated, and a second metric left bare, so one
    /// fixture can show both what the client sends and what it stays silent about.
    private func makeTile() throws -> NotifyTile {
        let metrics = [
            try makeMetric(label: "5h", value: "42", unit: "%", tintHex: "#59EBAD"),
            try makeMetric(label: "Week", value: "88"),
        ]
        return try #require(
            NotifyTile(
                title: "ClaudeBar",
                body: "Claude 5h 42% left",
                symbolName: NotifySymbol.quota,
                tintHex: "#59EBAD",
                progress: 42,
                trailing: "2:14",
                metrics: metrics
            )
        )
    }

    private func makeGauge() throws -> NotifyGauge {
        try #require(
            NotifyGauge(
                title: "ClaudeBar",
                value: "42",
                unit: "%",
                detail: "Claude 5h, resets in 2:14",
                symbolName: NotifySymbol.quota,
                tintHex: "#59EBAD",
                progress: 42
            )
        )
    }

    /// A gauge carrying nothing but its identity, for proving the fields ClaudeBar drives are
    /// stated as explicit nulls rather than quietly left out.
    private func makeTitleOnlyGauge() throws -> NotifyGauge {
        try #require(NotifyGauge(title: "ClaudeBar"))
    }

    // MARK: - Helpers

    private static func response(_ status: Int, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: host,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    /// A client whose single answer is `status` with `body`, for the tests that care only what the
    /// client makes of that answer.
    private func makeClient(
        status: Int,
        body: String = "{}",
        headers: [String: String]? = nil
    ) -> NotifyGatewayClient {
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willReturn((Data(body.utf8), Self.response(status, headers: headers)))
        return NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)
    }

    /// The JSON the client actually put on the wire.
    private func jsonBody(of request: URLRequest?) throws -> [String: Any] {
        let data = try #require(request?.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    // MARK: - Tile Start

    @Test
    func `tile start addresses the device and carries the token as a query item`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.startResponse.utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        _ = try await client.publishTile(tile, link: link, activityId: nil)

        // Then: the device dialect, and the per device secret in the query rather than a header
        #expect(
            capturedRequest?.url?.absoluteString
                == "https://push.getnotifyapp.com/live-activity/ABC12345?token=sekret-token-42"
        )
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test
    func `tile start asks for a tile of its own and sends the tile fields`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.startResponse.utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        _ = try await client.publishTile(tile, link: link, activityId: nil)

        // Then: `new` is what stops the start taking over a tile the user began elsewhere
        let body = try jsonBody(of: capturedRequest)
        #expect(body["new"] as? Bool == true)
        #expect(body["title"] as? String == "ClaudeBar")
        #expect(body["body"] as? String == "Claude 5h 42% left")
        #expect(body["symbol"] as? String == "gauge.with.needle")
        #expect(body["tint"] as? String == "#59EBAD")
        #expect(body["progress"] as? Double == 42)
        #expect(body["trailing"] as? String == "2:14")
    }

    @Test
    func `tile start spells metrics as objects with label value unit and color`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.startResponse.utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        _ = try await client.publishTile(tile, link: link, activityId: nil)

        // Then: the gateway reads metrics from the JSON body only, and names the cell color `color`
        let body = try jsonBody(of: capturedRequest)
        let metrics = try #require(body["metrics"] as? [[String: Any]])
        #expect(metrics.count == 2)
        #expect(metrics.first?["label"] as? String == "5h")
        #expect(metrics.first?["value"] as? String == "42")
        #expect(metrics.first?["unit"] as? String == "%")
        #expect(metrics.first?["color"] as? String == "#59EBAD")
        // The second cell left both optional fields nil, so neither key is spelled at all and it
        // inherits the tile's tint.
        #expect(metrics.last?.keys.sorted() == ["label", "value"])
    }

    @Test
    func `tile start returns the activity id the gateway assigned`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(status: 200, body: Self.startResponse)

        // When
        let identifier = try await client.publishTile(tile, link: link, activityId: nil)

        // Then
        #expect(identifier == Self.activityId)
    }

    // MARK: - Tile Update

    @Test
    func `tile update addresses that exact tile and never sends new`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.startResponse.utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        _ = try await client.publishTile(tile, link: link, activityId: Self.activityId)

        // Then: `new` on an update would leave the device with two tiles
        #expect(
            capturedRequest?.url?.absoluteString
                == "https://push.getnotifyapp.com/live-activity/LA7Q2ZKM?token=sekret-token-42"
        )
        let body = try jsonBody(of: capturedRequest)
        #expect(body.keys.contains("new") == false)
        #expect(body["title"] as? String == "ClaudeBar")
    }

    @Test
    func `tile update succeeds when the gateway has not pushed the content yet`() async throws {
        // Given: stored, but no reachable tile token right now
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(
            status: 200,
            body: """
            { "success": true, "activityId": "LA7Q2ZKM", "pushed": false }
            """
        )

        // When
        let identifier = try await client.publishTile(tile, link: link, activityId: Self.activityId)

        // Then: the content delivers when the device reports its token again, so this is a success
        // and not a reason to restart the tile
        #expect(identifier == Self.activityId)
    }

    // MARK: - Gauge Create

    @Test
    func `gauge create addresses the device with new and returns the widget id`() async throws {
        // Given
        let link = try makeLink()
        let gauge = try makeGauge()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.widgetResponse.utf8), Self.response(201))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        let identifier = try await client.publishGauge(gauge, link: link, widgetId: nil)

        // Then
        #expect(
            capturedRequest?.url?.absoluteString
                == "https://push.getnotifyapp.com/widgets/ABC12345?token=sekret-token-42"
        )
        #expect(capturedRequest?.httpMethod == "POST")
        let body = try jsonBody(of: capturedRequest)
        #expect(body["new"] as? Bool == true)
        #expect(body["title"] as? String == "ClaudeBar")
        #expect(body["value"] as? String == "42")
        #expect(body["unit"] as? String == "%")
        #expect(body["detail"] as? String == "Claude 5h, resets in 2:14")
        #expect(body["symbol"] as? String == "gauge.with.needle")
        #expect(body["tint"] as? String == "#59EBAD")
        #expect(body["progress"] as? Double == 42)
        #expect(identifier == Self.widgetId)
    }

    @Test
    func `gauge create accepts a 200 answer as well as a 201`() async throws {
        // Given: the gateway answers 200 when the create it received turned out to be an update
        let link = try makeLink()
        let gauge = try makeGauge()
        let client = makeClient(status: 200, body: Self.widgetResponse)

        // When
        let identifier = try await client.publishGauge(gauge, link: link, widgetId: nil)

        // Then
        #expect(identifier == Self.widgetId)
    }

    // MARK: - Gauge Update

    @Test
    func `gauge update addresses that exact widget and never sends new`() async throws {
        // Given
        let link = try makeLink()
        let gauge = try makeGauge()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.widgetResponse.utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        let identifier = try await client.publishGauge(gauge, link: link, widgetId: Self.widgetId)

        // Then
        #expect(
            capturedRequest?.url?.absoluteString
                == "https://push.getnotifyapp.com/widgets/WG4H2QZ1?token=sekret-token-42"
        )
        let body = try jsonBody(of: capturedRequest)
        #expect(body.keys.contains("new") == false)
        #expect(identifier == Self.widgetId)
    }

    @Test
    func `gauge body states a null for every field ClaudeBar drives but has no value for`() async throws {
        // Given: a gauge carrying nothing but its identity
        let link = try makeLink()
        let gauge = try makeTitleOnlyGauge()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.widgetResponse.utf8), Self.response(201))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        _ = try await client.publishGauge(gauge, link: link, widgetId: nil)

        // Then: the gateway merges rather than replaces, so a field left unsaid keeps whatever it
        // held. Every field ClaudeBar owns is therefore stated on every write, as an explicit null
        // when it has no value, or the widget would keep a percent sign and a ring belonging to a
        // reading it no longer shows.
        let body = try jsonBody(of: capturedRequest)
        #expect(body.keys.sorted() == ["detail", "new", "progress", "symbol", "tint", "title", "unit", "value"])
        #expect(body["progress"] is NSNull)
        #expect(body["unit"] is NSNull)
        #expect(body["detail"] is NSNull)
        #expect(body["value"] is NSNull)

        // The title is the widget's identity in the phone's picker, and the gateway refuses to
        // clear it, so it is the one field that is never a null.
        #expect(body["title"] as? String == gauge.title)
    }

    @Test
    func `tile body states a null for a countdown that is no longer known`() async throws {
        // Given: a tile whose headline quota reports no reset time and no percentage
        let link = try makeLink()
        let tile = try #require(
            NotifyTile(
                title: "ClaudeBar",
                body: "Amp Code Balance, $3.10 left",
                symbolName: NotifySymbol.quota,
                tintHex: QuotaStatus.healthy.notifyTintHex,
                progress: nil,
                trailing: nil,
                metrics: []
            )
        )
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.startResponse.utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When: updating a tile that previously carried a countdown and a bar
        _ = try await client.publishTile(tile, link: link, activityId: "LA7Q2ZKM")

        // Then: the fields with nothing to say are stated as null, which is what takes the old
        // countdown and the old bar off the Lock Screen
        let body = try jsonBody(of: capturedRequest)
        #expect(body["trailing"] is NSNull)
        #expect(body["progress"] is NSNull)
        #expect(body["metrics"] is NSNull)

        // The fields ClaudeBar never drives stay unsaid, so a tile can still carry whatever else
        // the user set up elsewhere.
        #expect(body["status"] == nil)
        #expect(body["endsIn"] == nil)
        #expect(body["steps"] == nil)
        #expect(body["button"] == nil)
    }

    // MARK: - The Home Screen Tile

    @Test
    func `a Home Screen tile create addresses the device with new and returns the screen widget id`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.screenWidgetResponse.utf8), Self.response(201))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        let identifier = try await client.publishScreenTile(tile, link: link, screenWidgetId: nil)

        // Then: the device dialect, and `new` for the same reason the other two surfaces send it.
        // A screen widget stays until the user removes it, so taking over one they already placed
        // would replace something of theirs permanently.
        #expect(
            capturedRequest?.url?.absoluteString
                == "https://push.getnotifyapp.com/screenwidgets/ABC12345?token=sekret-token-42"
        )
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try jsonBody(of: capturedRequest)
        #expect(body["new"] as? Bool == true)
        #expect(body["title"] as? String == "ClaudeBar")
        #expect(identifier == Self.screenWidgetId)
    }

    @Test
    func `a Home Screen tile create accepts a 200 answer as well as a 201`() async throws {
        // Given: the gateway answers 200 when the create it received turned out to be an update
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(status: 200, body: Self.screenWidgetResponse)

        // When
        let identifier = try await client.publishScreenTile(tile, link: link, screenWidgetId: nil)

        // Then
        #expect(identifier == Self.screenWidgetId)
    }

    @Test
    func `a Home Screen tile update addresses that exact widget and never sends new`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.screenWidgetResponse.utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        let identifier = try await client.publishScreenTile(
            tile,
            link: link,
            screenWidgetId: Self.screenWidgetId
        )

        // Then: `new` on an update would leave a second tile on the Home Screen for the user to
        // find and delete by hand
        #expect(
            capturedRequest?.url?.absoluteString
                == "https://push.getnotifyapp.com/screenwidgets/SW8N3PQ2?token=sekret-token-42"
        )
        let body = try jsonBody(of: capturedRequest)
        #expect(body.keys.contains("new") == false)
        #expect(body["title"] as? String == "ClaudeBar")
        #expect(identifier == Self.screenWidgetId)
    }

    @Test
    func `the Home Screen tile and the Live Activity are sent one identical body`() async throws {
        // Given one tile value, and a stub that answers whichever of the two routes it is handed
        let link = try makeLink()
        let tile = try makeTile()
        var capturedRequests: [URLRequest] = []
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequests.append(request)
                let isScreenWidget = request.url?.absoluteString.contains("/screenwidgets/") == true
                return (
                    Data((isScreenWidget ? Self.screenWidgetResponse : Self.startResponse).utf8),
                    Self.response(isScreenWidget ? 201 : 200)
                )
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When: the same tile goes to both surfaces
        _ = try await client.publishTile(tile, link: link, activityId: nil)
        _ = try await client.publishScreenTile(tile, link: link, screenWidgetId: nil)

        // Then: the two bodies differ in nothing at all. That is the premise of the whole feature:
        // the gateway derives the screen widget's content contract from its Live Activity module,
        // so one tile value drives both surfaces and the client keeps one builder for them. A
        // second builder here could only drift and put two different pictures of one quota on one
        // phone, which is the thing this test exists to catch.
        #expect(capturedRequests.count == 2)
        var liveActivityBody = try jsonBody(of: capturedRequests.first)
        var screenBody = try jsonBody(of: capturedRequests.last)
        liveActivityBody.removeValue(forKey: "new")
        screenBody.removeValue(forKey: "new")

        // Compared through NSDictionary rather than key by key, because the claim being made is
        // about the whole body, nested metrics row and explicit nulls included.
        #expect(NSDictionary(dictionary: liveActivityBody) == NSDictionary(dictionary: screenBody))

        // And the thing being compared is a real body rather than two empty dictionaries, which
        // would satisfy the equality above and prove nothing.
        #expect(screenBody["title"] as? String == "ClaudeBar")
        #expect((screenBody["metrics"] as? [[String: Any]])?.count == 2)
    }

    // MARK: - Device Kind Guards

    @Test
    func `a tile aimed at a Mac is refused without spending a request`() async throws {
        // Given a Mac link, and a network stub that would answer a start with a
        // perfectly good 200 if it were ever asked. That is the point of the
        // stub: nothing but the guard can keep this test green.
        let link = try makeLink(deviceId: Self.macDeviceId)
        let tile = try makeTile()
        let reason = try #require(NotifyDeviceKind.mac.liveActivityUnsupportedReason)
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.startResponse.utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When & Then: the gateway would answer a 400 saying the target cannot
        // show Live Activities at all, so what is at stake is which sentence the
        // user reads, and the link's own reason is the one that names the fix
        await #expect(throws: NotifyPublishError.liveActivityUnavailable(reason)) {
            _ = try await client.publishTile(tile, link: link, activityId: nil)
        }

        // And the half that matters: nothing went out. A captured request left
        // nil is what fails this test the day the guard is deleted.
        #expect(capturedRequest == nil)
    }

    @Test
    func `a tile aimed at a group is refused without spending a request`() async throws {
        // Given a group link, which is not a device at all: it fans a
        // notification out to its members and owns no Lock Screen to start on
        let link = try makeLink(deviceId: Self.groupDeviceId)
        let tile = try makeTile()
        let reason = try #require(NotifyDeviceKind.group.widgetUnsupportedReason)
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.startResponse.utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When & Then
        await #expect(throws: NotifyPublishError.liveActivityUnavailable(reason)) {
            _ = try await client.publishTile(tile, link: link, activityId: nil)
        }
        #expect(capturedRequest == nil)
    }

    @Test
    func `a gauge aimed at a browser is sent, because widgets carry no device gate`() async throws {
        // Given a browser link. A Live Activity would be refused for one, but the gateway is
        // explicit that widgets are different: there is no device-type gate on them and legacy,
        // WB and MC ids can all own one. Refusing this locally would be ClaudeBar inventing a
        // rule the service does not have, and taking a working surface away from the user.
        let link = try makeLink(deviceId: Self.webDeviceId)
        let gauge = try makeGauge()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.widgetResponse.utf8), Self.response(201))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        let widgetId = try await client.publishGauge(gauge, link: link, widgetId: nil)

        // Then: the write went out and its id came back
        #expect(widgetId == Self.widgetId)
        #expect(capturedRequest?.url?.absoluteString.contains("/widgets/\(Self.webDeviceId)") == true)
    }

    @Test
    func `a gauge aimed at a Mac is sent too`() async throws {
        let link = try makeLink(deviceId: Self.macDeviceId)
        let gauge = try makeGauge()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.widgetResponse.utf8), Self.response(201))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        let widgetId = try await client.publishGauge(gauge, link: link, widgetId: nil)

        #expect(widgetId == Self.widgetId)
        #expect(capturedRequest != nil)
    }

    @Test
    func `a gauge aimed at a group is refused without spending a request`() async throws {
        // Given a group link, which owns no widget surface either
        let link = try makeLink(deviceId: Self.groupDeviceId)
        let gauge = try makeGauge()
        let reason = try #require(NotifyDeviceKind.group.widgetUnsupportedReason)
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.widgetResponse.utf8), Self.response(201))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When & Then
        await #expect(throws: NotifyPublishError.invalidPayload(reason)) {
            _ = try await client.publishGauge(gauge, link: link, widgetId: nil)
        }
        #expect(capturedRequest == nil)
    }

    @Test
    func `a Home Screen tile aimed at a group is refused without spending a request`() async throws {
        // Given a group link, which owns no widget list for a Home Screen tile to sit in
        let link = try makeLink(deviceId: Self.groupDeviceId)
        let tile = try makeTile()
        let reason = try #require(NotifyDeviceKind.group.screenWidgetUnsupportedReason)
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.screenWidgetResponse.utf8), Self.response(201))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When & Then: `invalidPayload` rather than `liveActivityUnavailable`, because no Live
        // Activity is involved and that error's remedies would send the user somewhere useless
        await #expect(throws: NotifyPublishError.invalidPayload(reason)) {
            _ = try await client.publishScreenTile(tile, link: link, screenWidgetId: nil)
        }
        #expect(capturedRequest == nil)
    }

    @Test
    func `a Home Screen tile aimed at a Mac is sent, because screen widgets carry no device gate`() async throws {
        // Given a Mac link. A Live Activity would be refused for one, and a screen widget is not:
        // the gateway is explicit that this route has no device-type gate and that legacy, IO, WB
        // and MC ids can each own one. Refusing it here would be ClaudeBar inventing a rule the
        // service does not have.
        let link = try makeLink(deviceId: Self.macDeviceId)
        let tile = try makeTile()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.screenWidgetResponse.utf8), Self.response(201))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        let identifier = try await client.publishScreenTile(tile, link: link, screenWidgetId: nil)

        // Then: the write went out and its id came back
        #expect(identifier == Self.screenWidgetId)
        #expect(
            capturedRequest?.url?.absoluteString.contains("/screenwidgets/\(Self.macDeviceId)") == true
        )
    }

    @Test
    func `a Home Screen tile aimed at a browser is sent too`() async throws {
        let link = try makeLink(deviceId: Self.webDeviceId)
        let tile = try makeTile()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.screenWidgetResponse.utf8), Self.response(201))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        let identifier = try await client.publishScreenTile(tile, link: link, screenWidgetId: nil)

        #expect(identifier == Self.screenWidgetId)
        #expect(
            capturedRequest?.url?.absoluteString.contains("/screenwidgets/\(Self.webDeviceId)") == true
        )
    }

    @Test
    func `a tile for an eight character app device still goes out`() async throws {
        // Given the ordinary case: the legacy eight character format, which an
        // iPhone and an older poll only Mac listener share. Nothing local can
        // tell those two apart, so this one is sent and the gateway decides.
        let link = try makeLink()
        let tile = try makeTile()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.startResponse.utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        let identifier = try await client.publishTile(tile, link: link, activityId: nil)

        // Then: the guard reads the namespace, so it cannot become a blanket
        // refusal that quietly stops the feature working at all
        #expect(
            capturedRequest?.url?.absoluteString
                == "https://push.getnotifyapp.com/live-activity/ABC12345?token=sekret-token-42"
        )
        #expect(identifier == Self.activityId)
    }

    @Test
    func `a gauge for an eight character app device still goes out`() async throws {
        // Given
        let link = try makeLink()
        let gauge = try makeGauge()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.widgetResponse.utf8), Self.response(201))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        let identifier = try await client.publishGauge(gauge, link: link, widgetId: nil)

        // Then
        #expect(
            capturedRequest?.url?.absoluteString
                == "https://push.getnotifyapp.com/widgets/ABC12345?token=sekret-token-42"
        )
        #expect(identifier == Self.widgetId)
    }

    // MARK: - Ending the Tile


    @Test
    func `endTile deletes the tile and clamps keepFor to the gateway ceiling`() async throws {
        // Given
        let link = try makeLink()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data("{\"success\": true}".utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When: more lingering than the gateway's four hour ceiling allows
        try await client.endTile(link: link, activityId: Self.activityId, keepFor: 99_999)

        // Then: clamped rather than rejected, because the wait is only decorating the end call
        #expect(
            capturedRequest?.url?.absoluteString
                == "https://push.getnotifyapp.com/live-activity/LA7Q2ZKM?token=sekret-token-42&keepFor=14400"
        )
        #expect(capturedRequest?.httpMethod == "DELETE")
    }

    @Test
    func `endTile clamps a negative keepFor to zero`() async throws {
        // Given
        let link = try makeLink()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data("{\"success\": true}".utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        try await client.endTile(link: link, activityId: Self.activityId, keepFor: -30)

        // Then
        #expect(
            capturedRequest?.url?.absoluteString
                == "https://push.getnotifyapp.com/live-activity/LA7Q2ZKM?token=sekret-token-42&keepFor=0"
        )
    }

    @Test
    func `endTile treats a 410 as the tile already being gone`() async throws {
        // Given: dismissed, ended or reaped before ClaudeBar asked
        let link = try makeLink()
        let client = makeClient(status: 410, body: """
        { "error": "LiveActivityGone", "message": "already ended" }
        """)

        // When & Then: the outcome the caller asked for, so nothing is thrown
        try await client.endTile(link: link, activityId: Self.activityId, keepFor: 60)
    }

    // MARK: - Device Info

    @Test
    func `deviceInfo reads the link route and maps the flat response`() async throws {
        // Given
        let link = try makeLink()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.linkResponse.utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        let info = try await client.deviceInfo(link: link)

        // Then: a bare read, because a GET carrying content parameters would act instead
        #expect(
            capturedRequest?.url?.absoluteString
                == "https://push.getnotifyapp.com/link?id=ABC12345&token=sekret-token-42"
        )
        #expect(capturedRequest?.httpMethod == "GET")
        #expect(capturedRequest?.httpBody == nil)
        #expect(info == NotifyDeviceInfo(deviceId: "ABC12345", name: "Apollo", platform: "iOS"))
    }

    @Test
    func `deviceInfo reports a pair the gateway does not recognise as rejected credentials`() async throws {
        // Given: the answer the live gateway actually gives for a wrong id or token. This route
        // carries its own error envelope and answers 404 rather than the 403 every other route
        // uses, and gives the same 404 for a wrong token and for an id that does not exist, so it
        // cannot be used to enumerate ids.
        let link = try makeLink()
        let body = """
        {
          "success": false,
          "error": "Invalid credentials",
          "code": "NOT_FOUND",
          "message": "No device or group found with the provided ID and token combination"
        }
        """
        let client = makeClient(status: 404, body: body)

        // When and Then: the person who just pasted their credentials gets the sentence about
        // credentials, not a bare status code
        await #expect(throws: NotifyPublishError.rejectedCredentials) {
            _ = try await client.deviceInfo(link: link)
        }
    }

    @Test
    func `deviceInfo rejects a link that points at a group`() async throws {
        // Given: the same route describes groups, and a group carries neither tile nor widget
        let link = try makeLink()
        let client = makeClient(status: 200, body: """
        {
          "success": true,
          "type": "group",
          "id": "ABC12345",
          "name": "Family",
          "message": "ok"
        }
        """)

        // When & Then
        do {
            _ = try await client.deviceInfo(link: link)
            Issue.record("Expected a group link to be refused")
        } catch let error as NotifyPublishError {
            guard case .invalidPayload(let message) = error else {
                Issue.record("Expected .invalidPayload, got \(error)")
                return
            }
            #expect(message.contains("group"))
        }
    }

    // MARK: - Error Mapping

    @Test
    func `400 becomes invalidPayload carrying the gateway message`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(status: 400, body: """
        { "error": "ValidationError", "message": "title must not be empty" }
        """)

        // When & Then: the gateway names the field, so its own wording is what the pane shows
        await #expect(throws: NotifyPublishError.invalidPayload("title must not be empty")) {
            try await client.publishTile(tile, link: link, activityId: nil)
        }
    }

    @Test
    func `403 becomes rejectedCredentials`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(status: 403, body: """
        { "error": "Forbidden", "message": "invalid token" }
        """)

        // When & Then: missing, wrong, unknown and somebody else's id are one answer by design
        await #expect(throws: NotifyPublishError.rejectedCredentials) {
            try await client.publishTile(tile, link: link, activityId: nil)
        }
    }

    @Test
    func `409 becomes liveActivityUnavailable`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(status: 409, body: """
        { "error": "LiveActivityNoCredential", "message": "Open the Notify! app once on the device." }
        """)

        // When & Then: the gateway's explanation distinguishes the three causes, so it is kept
        await #expect(
            throws: NotifyPublishError.liveActivityUnavailable("Open the Notify! app once on the device.")
        ) {
            try await client.publishTile(tile, link: link, activityId: nil)
        }
    }

    @Test
    func `409 on the Home Screen route becomes invalidPayload, not liveActivityUnavailable`() async throws {
        // Given the one thing a 409 can mean here: the device dialect found several screen widgets
        // and cannot tell which was meant. ClaudeBar creates its own and addresses it by SW id
        // afterwards, so it should never see this.
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(status: 409, body: """
        { "error": "ScreenWidgetAmbiguous", "message": "Several screen widgets exist on this device." }
        """)

        // When & Then: the shared mapping reads a 409 as a Live Activity problem, because that is
        // what it means on the route it was written for. Left alone it would tell somebody to open
        // the Notify! app about their Live Activities, which is a wrong answer to a question about
        // a Home Screen widget.
        await #expect(
            throws: NotifyPublishError.invalidPayload("Several screen widgets exist on this device.")
        ) {
            _ = try await client.publishScreenTile(tile, link: link, screenWidgetId: nil)
        }
    }

    @Test
    func `503 is the Home Screen surface being switched off, and worth trying again later`() async throws {
        // Given the server side kill switch this surface shipped behind, so a ClaudeBar that
        // supports it can meet a gateway that is not serving it yet
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(status: 503, body: """
        { "error": "ScreenWidgetsDisabled", "message": "Screen widgets are not enabled." }
        """)

        // When
        do {
            _ = try await client.publishScreenTile(tile, link: link, screenWidgetId: nil)
            Issue.record("Expected the kill switch to surface")
        } catch let error as NotifyPublishError {
            // Then: nothing is wrong with ClaudeBar, the credentials or the content, and the only
            // remedy is the day the surface is switched on. The gateway's own sentence is not
            // carried, and that costs nothing: an empty message picks the error's own wording,
            // which is the sentence to put in front of a user however the server phrased it.
            #expect(error == .surfaceSwitchedOff(""))
            #expect(error.errorDescription?.contains("try again later") == true)

            // And it is retryable, which is what keeps the driver backing off rather than giving
            // up on the surface until something else changes.
            #expect(error.isRetryable)
        }
    }

    @Test
    func `410 on an update becomes tileGone`() async throws {
        // Given: the user swiped the tile away, so it can never be updated again
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(status: 410, body: """
        { "error": "LiveActivityGone", "message": "dismissed" }
        """)

        // When & Then
        await #expect(throws: NotifyPublishError.tileGone) {
            try await client.publishTile(tile, link: link, activityId: Self.activityId)
        }
    }

    @Test
    func `429 takes its wait from retryAfterSeconds in the body`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(status: 429, body: """
        {
          "error": "LiveActivityBackoff",
          "message": "too many unanswered starts",
          "unansweredStarts": 4,
          "retryAfterSeconds": 10800,
          "openingTheAppMayHelp": true
        }
        """)

        // When & Then: the body's number comes from the ladder the gateway is enforcing
        await #expect(
            throws: NotifyPublishError.backoff(retryAfter: 10800, openingTheAppMayHelp: true)
        ) {
            try await client.publishTile(tile, link: link, activityId: nil)
        }
    }

    @Test
    func `429 without a body wait falls back to the Retry-After header`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(
            status: 429,
            body: """
            { "error": "LiveActivityBackoff", "message": "too many unanswered starts" }
            """,
            headers: ["Retry-After": "1800"]
        )

        // When & Then: only the numeric header form is read, and nothing claimed the app would help
        await #expect(
            throws: NotifyPublishError.backoff(retryAfter: 1800, openingTheAppMayHelp: false)
        ) {
            try await client.publishTile(tile, link: link, activityId: nil)
        }
    }

    @Test
    func `502 with an unknown delivery state becomes deliveryUnconfirmed`() async throws {
        // Given: Apple never answered, so a tile may well exist
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(status: 502, body: """
        {
          "error": "LiveActivityStartFailure",
          "message": "no answer from APNs",
          "deliveryState": "unknown",
          "activityId": "LA7Q2ZKM"
        }
        """)

        // When & Then: the id rides along so the caller can poll rather than risk a second tile
        await #expect(throws: NotifyPublishError.deliveryUnconfirmed(activityId: Self.activityId)) {
            try await client.publishTile(tile, link: link, activityId: nil)
        }
    }

    @Test
    func `502 that delivered nothing becomes a wait, not an immediate retry`() async throws {
        // Given: Apple refused the start outright and the gateway named how long to sit out
        let link = try makeLink()
        let tile = try makeTile()
        let body = """
        {
          "error": "Bad Gateway",
          "message": "Apple refused the start",
          "deliveryState": "not-delivered",
          "retryAfterSeconds": 900
        }
        """
        let client = makeClient(status: 502, body: body)

        // When and Then: no tile exists, so starting again is safe, but every unanswered start
        // counts toward a push to start ladder that reaches six hours. Waiting the gateway's own
        // 900 seconds is what keeps a transient refusal from becoming a lockout.
        await #expect(throws: NotifyPublishError.backoff(retryAfter: 900, openingTheAppMayHelp: false)) {
            _ = try await client.publishTile(tile, link: link, activityId: nil)
        }
    }

    @Test
    func `the credential check refuses to be answered from the URL cache`() async throws {
        // Given
        let link = try makeLink()
        var capturedRequest: URLRequest?
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (Data(Self.linkResponse.utf8), Self.response(200))
            }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When
        _ = try await client.deviceInfo(link: link)

        // Then: this is the one GET in the feature and its URL carries the device token. A
        // cacheable answer would put that secret in URLCache's on-disk store in plaintext.
        #expect(capturedRequest?.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test
    func `a request that never completes becomes transportFailed`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        let network = MockNetworkClient()
        given(network)
            .request(.any)
            .willProduce { _ in throw URLError(.notConnectedToInternet) }
        let client = NotifyGatewayClient(networkClient: network, host: Self.host, timeout: 1)

        // When & Then: no caller ever sees a URLError
        do {
            _ = try await client.publishTile(tile, link: link, activityId: nil)
            Issue.record("Expected the transport failure to surface")
        } catch let error as NotifyPublishError {
            // The message is URLError's own localized text, which depends on the locale, so only
            // the case itself can be asserted here.
            guard case .transportFailed = error else {
                Issue.record("Expected .transportFailed, got \(error)")
                return
            }
        }
    }

    @Test
    func `an unexpected 500 becomes unexpectedStatus`() async throws {
        // Given
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(status: 500)

        // When & Then
        await #expect(throws: NotifyPublishError.unexpectedStatus(500)) {
            try await client.publishTile(tile, link: link, activityId: nil)
        }
    }

    @Test
    func `a success carrying an unreadable body becomes malformedResponse`() async throws {
        // Given: the status said yes but the body is not the JSON the route documents
        let link = try makeLink()
        let tile = try makeTile()
        let client = makeClient(status: 200, body: "<html>gateway upgrade in progress</html>")

        // When & Then
        await #expect(throws: NotifyPublishError.malformedResponse) {
            try await client.publishTile(tile, link: link, activityId: nil)
        }
    }
}
