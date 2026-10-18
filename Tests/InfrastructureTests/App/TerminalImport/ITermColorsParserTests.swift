import Testing
import Foundation
@testable import Infrastructure

@Suite
struct ITermColorsParserTests {

    static let minimalItermcolors = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Background Color</key>
        <dict>
            <key>Red Component</key><real>0.15686</real>
            <key>Green Component</key><real>0.16471</real>
            <key>Blue Component</key><real>0.21176</real>
            <key>Alpha Component</key><real>1</real>
            <key>Color Space</key><string>sRGB</string>
        </dict>
        <key>Foreground Color</key>
        <dict>
            <key>Red Component</key><real>0.97255</real>
            <key>Green Component</key><real>0.97255</real>
            <key>Blue Component</key><real>0.94902</real>
            <key>Alpha Component</key><real>1</real>
            <key>Color Space</key><string>sRGB</string>
        </dict>
        <key>Bold Color</key>
        <dict>
            <key>Red Component</key><real>0.97255</real>
            <key>Green Component</key><real>0.97255</real>
            <key>Blue Component</key><real>0.94902</real>
            <key>Alpha Component</key><real>1</real>
            <key>Color Space</key><string>sRGB</string>
        </dict>
        <key>Cursor Color</key>
        <dict>
            <key>Red Component</key><real>0.97255</real>
            <key>Green Component</key><real>0.97255</real>
            <key>Blue Component</key><real>0.94902</real>
            <key>Alpha Component</key><real>1</real>
            <key>Color Space</key><string>sRGB</string>
        </dict>
        <key>Selection Color</key>
        <dict>
            <key>Red Component</key><real>0.26667</real>
            <key>Green Component</key><real>0.27843</real>
            <key>Blue Component</key><real>0.35294</real>
            <key>Alpha Component</key><real>1</real>
            <key>Color Space</key><string>sRGB</string>
        </dict>
        <key>Selected Text Color</key>
        <dict>
            <key>Red Component</key><real>1</real>
            <key>Green Component</key><real>1</real>
            <key>Blue Component</key><real>1</real>
            <key>Alpha Component</key><real>1</real>
            <key>Color Space</key><string>sRGB</string>
        </dict>
        <key>Ansi 0 Color</key>
        <dict><key>Red Component</key><real>0.12941</real><key>Green Component</key><real>0.13333</real><key>Blue Component</key><real>0.17255</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 1 Color</key>
        <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>0.33333</real><key>Blue Component</key><real>0.33333</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 2 Color</key>
        <dict><key>Red Component</key><real>0.31373</real><key>Green Component</key><real>0.98039</real><key>Blue Component</key><real>0.48235</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 3 Color</key>
        <dict><key>Red Component</key><real>0.94510</real><key>Green Component</key><real>0.98039</real><key>Blue Component</key><real>0.54902</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 4 Color</key>
        <dict><key>Red Component</key><real>0.74118</real><key>Green Component</key><real>0.57647</real><key>Blue Component</key><real>0.97647</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 5 Color</key>
        <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>0.47451</real><key>Blue Component</key><real>0.77647</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 6 Color</key>
        <dict><key>Red Component</key><real>0.54510</real><key>Green Component</key><real>0.91373</real><key>Blue Component</key><real>0.99216</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 7 Color</key>
        <dict><key>Red Component</key><real>0.97255</real><key>Green Component</key><real>0.97255</real><key>Blue Component</key><real>0.94902</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 8 Color</key>
        <dict><key>Red Component</key><real>0.38431</real><key>Green Component</key><real>0.44706</real><key>Blue Component</key><real>0.64314</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 9 Color</key>
        <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>0.43137</real><key>Blue Component</key><real>0.43137</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 10 Color</key>
        <dict><key>Red Component</key><real>0.41176</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>0.58039</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 11 Color</key>
        <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>0.64706</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 12 Color</key>
        <dict><key>Red Component</key><real>0.83922</real><key>Green Component</key><real>0.67451</real><key>Blue Component</key><real>1</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 13 Color</key>
        <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>0.57255</real><key>Blue Component</key><real>0.87451</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 14 Color</key>
        <dict><key>Red Component</key><real>0.64314</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>1</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 15 Color</key>
        <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>1</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
    </dict>
    </plist>
    """

    @Test func `should import an iTerm scheme's name, background and foreground colours`() throws {
        let data = Data(Self.minimalItermcolors.utf8)
        let scheme = try ITermColorsParser.parse(from: data, name: "Dracula")
        #expect(scheme.name == "Dracula")
        #expect(abs(scheme.background.red - 0.15686) < 0.001)
        #expect(abs(scheme.background.green - 0.16471) < 0.001)
        #expect(abs(scheme.background.blue - 0.21176) < 0.001)
        #expect(abs(scheme.foreground.red - 0.97255) < 0.001)
    }

    @Test func `should import all 16 ANSI colours of an iTerm scheme`() throws {
        let data = Data(Self.minimalItermcolors.utf8)
        let scheme = try ITermColorsParser.parse(from: data, name: "Dracula")
        #expect(scheme.ansiColors.count == 16)
        #expect(scheme.isValid)
        #expect(abs(scheme.black.red - 0.12941) < 0.001)
        #expect(abs(scheme.red.red - 1.0) < 0.001)
        #expect(abs(scheme.red.green - 0.33333) < 0.001)
        #expect(abs(scheme.cyan.red - 0.54510) < 0.001)
        #expect(abs(scheme.brightWhite.red - 1.0) < 0.001)
    }

    @Test func `should import the bold, cursor and selection colours when the scheme has them`() throws {
        let data = Data(Self.minimalItermcolors.utf8)
        let scheme = try ITermColorsParser.parse(from: data, name: "Dracula")
        #expect(scheme.boldText != nil)
        #expect(scheme.cursor != nil)
        #expect(scheme.selection != nil)
        #expect(scheme.selectionText != nil)
    }

    @Test func `should see a scheme with a dark background as dark`() throws {
        let data = Data(Self.minimalItermcolors.utf8)
        let scheme = try ITermColorsParser.parse(from: data, name: "Dracula")
        #expect(scheme.isDark)
    }

    @Test func `should refuse an iTerm scheme with no background colour`() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Foreground Color</key>
            <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>1</real></dict>
        </dict>
        </plist>
        """
        let data = Data(xml.utf8)
        #expect(throws: ITermColorsParserError.self) {
            try ITermColorsParser.parse(from: data, name: "Bad")
        }
    }

    @Test func `should refuse an iTerm scheme missing an ANSI colour`() {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Background Color</key>
            <dict><key>Red Component</key><real>0</real><key>Green Component</key><real>0</real><key>Blue Component</key><real>0</real></dict>
            <key>Foreground Color</key>
            <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>1</real></dict>
        """
        for i in 0..<15 {
            xml += """
                <key>Ansi \(i) Color</key>
                <dict><key>Red Component</key><real>0.5</real><key>Green Component</key><real>0.5</real><key>Blue Component</key><real>0.5</real></dict>
            """
        }
        xml += "</dict></plist>"
        let data = Data(xml.utf8)
        #expect(throws: ITermColorsParserError.self) {
            try ITermColorsParser.parse(from: data, name: "Incomplete")
        }
    }

    @Test func `should import an older iTerm scheme without alpha or colour space as opaque`() throws {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Background Color</key>
            <dict><key>Red Component</key><real>0.1</real><key>Green Component</key><real>0.1</real><key>Blue Component</key><real>0.1</real></dict>
            <key>Foreground Color</key>
            <dict><key>Red Component</key><real>0.9</real><key>Green Component</key><real>0.9</real><key>Blue Component</key><real>0.9</real></dict>
        """
        for i in 0..<16 {
            xml += """
            <key>Ansi \(i) Color</key>
            <dict><key>Red Component</key><real>0.\(i)</real><key>Green Component</key><real>0.\(i)</real><key>Blue Component</key><real>0.\(i)</real></dict>
            """
        }
        xml += "</dict></plist>"
        let data = Data(xml.utf8)
        let scheme = try ITermColorsParser.parse(from: data, name: "Legacy")
        #expect(scheme.background.alpha == 1.0)
        #expect(scheme.ansiColors.count == 16)
    }
}
