import Testing
import AppKit
import Kit
@testable import ClaudeBar

@Suite @MainActor
struct MenuBarNativeIconsTests {
    private func pixels(_ image: NSImage) throws -> NSBitmapImageRep {
        // Force deferred drawing at Retina scale; do not depend on NSApp's theme.
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2),
            pixelsHigh: Int(image.size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = image.size
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func visibleColors(_ image: NSImage) throws -> [NSColor] {
        let bitmap = try pixels(image)
        return (0..<bitmap.pixelsHigh).flatMap { y in
            (0..<bitmap.pixelsWide).compactMap { x in
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.2 else { return nil }
                return c
            }
        }
    }

    @Test(arguments: [false, true])
    func `should tint a native icon to the menu bar's ink and keep its see-through space`(dark: Bool) throws {
        let source = NSImage(size: NSSize(width: 32, height: 16), flipped: false) { _ in
            NSColor.red.setFill()
            NSRect(x: 8, y: 4, width: 16, height: 8).fill()
            return true
        }
        let image = StatusItemLabelDriver.fittedProviderIcon(source, ink: dark ? .white : .black)
        let bitmap = try pixels(image)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0)
        let colors = try visibleColors(image)
        #expect(!colors.isEmpty)
        let expected = dark ? 1.0 : 0.0
        #expect(colors.allSatisfy { abs($0.redComponent-expected) < 0.01 && abs($0.greenComponent-expected) < 0.01 && abs($0.blueComponent-expected) < 0.01 })
        #expect(!source.isTemplate) // Shared artwork is never mutated.
    }

    @Test func `should draw every bundled menu bar icon as a mark with see-through space, not an opaque tile`() throws {
        for name in ["Claude", "Codex", "Copilot", "Cursor", "Gemini", "Antigravity", "Zai", "Bedrock", "AmpCode", "Kimi", "MiniMax", "Mistral", "OpenCode", "Omp", "Grok", "CommandCode", "Vercel", "Cline", "Warp", "Devin", "Windsurf"] {
            let mask = try #require(NSImage(named: name + "IconMenuBar"), "Missing bundled template for \(name)")
            let image = StatusItemLabelDriver.fittedProviderIcon(mask, ink: .black)
            let bitmap = try pixels(image)
            #expect(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0)
            let occupied = try visibleColors(image).count
            #expect(occupied > 10 && occupied < bitmap.pixelsWide * bitmap.pixelsHigh * 3 / 4, "Opaque tile or empty mark for \(name)")
        }
        let brand = try visibleColors(StatusItemLabelDriver.providerIcon(for: "codex", native: false, dark: false))
        #expect(brand.contains { abs($0.redComponent-$0.greenComponent) > 0.1 })
    }

    @Test(arguments: [false, true])
    func `should draw every provider's native icon in neutral ink, including added accounts and unknown providers`(dark: Bool) throws {
        for id in ["claude", "codex", "codex.work", "gemini", "copilot", "antigravity", "zai", "bedrock", "ampcode", "kimi", "kiro", "minimax", "deepseek", "cursor", "mistral", "opencode-go", "omp", "grok", "commandcode", "vercel-gateway", "cline", "warp", "devin", "windsurf", "jetbrains", "openai", "extension.unknown"] {
            let colors = try visibleColors(StatusItemLabelDriver.providerIcon(for: id, native: true, dark: dark))
            #expect(!colors.isEmpty, "Missing icon for \(id)")
            #expect(colors.allSatisfy { abs($0.redComponent-$0.greenComponent) < 0.01 && abs($0.greenComponent-$0.blueComponent) < 0.01 }, "Colored pixels for \(id)")
            #expect(colors.allSatisfy { dark ? $0.redComponent > 0.99 : $0.redComponent < 0.01 })
        }
    }

    @Test func `should redraw the menu bar in native-icon mode and leave the colored quotas unchanged`() throws {
        var content = StatusItemLabelDriver.LabelContent(label: MenuBarLabel(text: "40%", status: .critical),
            primaryProviderId: "codex", primaryProviderName: "Codex", fallbackStatus: .critical,
            sessionPhase: nil, themeModeId: "dark")
        let original = content
        content.nativeMenuBarIconsEnabled = true
        #expect(content != original)
        let colored = try pixels(StatusItemLabelDriver.compose(original, theme: DarkTheme()))
        let native = try pixels(StatusItemLabelDriver.compose(content, theme: DarkTheme()))
        #expect(colored.pixelsWide == native.pixelsWide)
        // First 16pt is the logo, followed by 3pt spacing; every quota pixel stays identical.
        for y in 0..<native.pixelsHigh {
            for x in 38..<native.pixelsWide {
                #expect(native.colorAt(x: x, y: y) == colored.colorAt(x: x, y: y))
            }
        }
        let colors = try visibleColors(StatusItemLabelDriver.compose(content, theme: DarkTheme()))
        #expect(colors.contains { abs($0.redComponent-$0.greenComponent) > 0.1 })
        let darkContent = content
        content.isDarkAppearance = false
        #expect(content != darkContent)
    }
}
