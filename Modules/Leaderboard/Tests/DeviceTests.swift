import Foundation
import Testing
@testable import Leaderboard

/// What a device is called, the code a new one shows, and a device as `/me` lists it.
@Suite
struct DeviceTests {
    // MARK: - The label

    @Test func `should take a label the person typed, without the spaces around it`() {
        #expect(DeviceLabel("  Mac mini  ")?.value == "Mac mini")
    }

    @Test(arguments: ["", "   ", String(repeating: "a", count: 41), "Mac\nmini", "Mac\u{7}"])
    func `should refuse a label the server would refuse: empty, over 40 characters, or with a control character`(text: String) {
        #expect(DeviceLabel(text) == nil)
    }

    @Test func `should take a label of exactly 40 characters`() {
        #expect(DeviceLabel(String(repeating: "a", count: 40)) != nil)
    }

    // MARK: - The code

    @Test(arguments: ["WDJB-MJHT", "wdjbmjht", "wdjb mjht", " WDJB-mjht "])
    func `should read a code however it's typed: case, dash and spaces`(typed: String) {
        #expect(DeviceCode(typed)?.value == "WDJBMJHT")
    }

    @Test func `should show a code in two groups of four`() {
        #expect(DeviceCode("wdjbmjht")?.description == "WDJB-MJHT")
    }

    @Test(arguments: ["WDJB-MJH", "WDJB-MJHTX", "WDJB-MJHA", "WDJB-MJH1"])
    func `should refuse a code that isn't 8 of RFC 8628's consonants`(typed: String) {
        #expect(DeviceCode(typed) == nil)
    }

    // MARK: - A device on /me

    @Test func `should read a device on /me, removed or in use`() throws {
        let json = #"""
        [{"publicKey":"k1","label":"MacBook Pro","addedAt":"2026-10-01T08:00:00Z","removedAt":null,"removedBy":null},
         {"publicKey":"k2","label":"Mac mini","addedAt":"2026-10-03T08:00:00.250Z","removedAt":"2026-10-04T09:30:00Z",
          "removedBy":{"publicKey":"k1","label":"MacBook Pro"}}]
        """#

        let devices = try JSONDecoder().decode([Device].self, from: Data(json.utf8))

        #expect(devices[0].publicKey == "k1")
        #expect(devices[0].label == "MacBook Pro")
        #expect(devices[0].addedAt == Date(timeIntervalSince1970: 1_790_841_600))
        #expect(devices[0].removedAt == nil && devices[0].removedBy == nil)
        #expect(devices[1].addedAt == Date(timeIntervalSince1970: 1_791_014_400.25))
        #expect(devices[1].removedAt == Date(timeIntervalSince1970: 1_791_106_200))
        #expect(devices[1].removedBy == DeviceRef(publicKey: "k1", label: "MacBook Pro"))
    }

    /// §5 doesn't say how the server writes a time, so the forms a Worker
    /// on D1 is likely to send all read as the same instant.
    @Test(arguments: [#""2026-10-01T08:00:00Z""#, #""2026-10-01T08:00:00.000Z""#, #""2026-10-01 08:00:00""#,
                      "1790841600", "1790841600000"])
    func `should read a time however the server writes it`(written: String) throws {
        let json = #"{"publicKey":"k1","label":"Mac","addedAt":"# + written + "}"

        let device = try JSONDecoder().decode(Device.self, from: Data(json.utf8))

        #expect(device.addedAt == Date(timeIntervalSince1970: 1_790_841_600))
    }

    @Test func `should refuse a device whose time it can't read, rather than guess one`() {
        let json = #"{"publicKey":"k1","label":"Mac","addedAt":"last Tuesday"}"#

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Device.self, from: Data(json.utf8)) }
    }

    /// Settings' *Export…* writes `/me`'s answer with a plain `JSONEncoder`; read
    /// back, every device keeps the times the server gave it.
    @Test func `should write a member's devices so their times read back as the same instants`() throws {
        let json = #"""
        {"username":"tokenwhale","visible":true,"standing":null,"days":[],"devices":[
         {"publicKey":"k1","label":"MacBook Pro","addedAt":"2026-10-01T08:00:00Z","removedAt":null,"removedBy":null},
         {"publicKey":"k2","label":"Mac mini","addedAt":1791014400123,"removedAt":"2026-10-04 09:30:00",
          "removedBy":{"publicKey":"k1","label":"MacBook Pro"}}]}
        """#
        let summary = try JSONDecoder().decode(MemberSummary.self, from: Data(json.utf8))

        let exported = try JSONEncoder().encode(summary)

        let readBack = try JSONDecoder().decode(MemberSummary.self, from: exported).devices
        #expect(readBack.map(\.addedAt) == [Date(timeIntervalSince1970: 1_790_841_600), Date(timeIntervalSince1970: 1_791_014_400.123)])
        #expect(readBack.map(\.removedAt) == [nil, Date(timeIntervalSince1970: 1_791_106_200)])
        #expect(readBack == summary.devices)
    }
}
