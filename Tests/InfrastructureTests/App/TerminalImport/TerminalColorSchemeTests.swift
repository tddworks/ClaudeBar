// Tests/InfrastructureTests/App/TerminalImport/TerminalColorSchemeTests.swift
import Testing
import Foundation
@testable import Infrastructure

@Suite
struct TerminalColorSchemeTests {

    @Test func `should keep an imported colour exactly when saved and loaded`() throws {
        let color = TerminalColorScheme.RGBColor(red: 0.114, green: 0.145, blue: 0.169, alpha: 1.0)
        let data = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(TerminalColorScheme.RGBColor.self, from: data)
        #expect(decoded.red == 0.114)
        #expect(decoded.green == 0.145)
        #expect(decoded.blue == 0.169)
        #expect(decoded.alpha == 1.0)
    }

    @Test func `should keep an imported scheme's name, ANSI colours and optional colours when saved and loaded`() throws {
        let scheme = TerminalColorScheme(
            name: "Test",
            background: .init(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0),
            foreground: .init(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0),
            boldText: .init(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0),
            cursor: nil,
            selection: nil,
            selectionText: nil,
            ansiColors: (0..<16).map { i in
                TerminalColorScheme.RGBColor(
                    red: Double(i) / 15.0,
                    green: Double(i) / 15.0,
                    blue: Double(i) / 15.0,
                    alpha: 1.0
                )
            }
        )
        let data = try JSONEncoder().encode(scheme)
        let decoded = try JSONDecoder().decode(TerminalColorScheme.self, from: data)
        #expect(decoded.name == "Test")
        #expect(decoded.ansiColors.count == 16)
        #expect(decoded.boldText != nil)
        #expect(decoded.cursor == nil)
    }

    @Test func `should not count a scheme without 16 ANSI colours as usable`() {
        let scheme = TerminalColorScheme(
            name: "Bad",
            background: .init(red: 0, green: 0, blue: 0, alpha: 1),
            foreground: .init(red: 1, green: 1, blue: 1, alpha: 1),
            boldText: nil,
            cursor: nil,
            selection: nil,
            selectionText: nil,
            ansiColors: [.init(red: 0, green: 0, blue: 0, alpha: 1)]
        )
        #expect(scheme.isValid == false)
    }

    @Test func `should see white as bright and black as dark`() {
        let white = TerminalColorScheme.RGBColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        let black = TerminalColorScheme.RGBColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        #expect(white.luminance > 0.9)
        #expect(black.luminance < 0.1)
    }

    @Test func `should make a colour brighter when lightened and darker when darkened`() {
        let color = TerminalColorScheme.RGBColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        let lighter = color.lightened(by: 0.1)
        let darker = color.darkened(by: 0.1)
        #expect(lighter.luminance > color.luminance)
        #expect(darker.luminance < color.luminance)
    }
}
