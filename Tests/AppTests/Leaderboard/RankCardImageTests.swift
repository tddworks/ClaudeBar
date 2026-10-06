import AppKit
import Foundation
import Testing
import Domain
@testable import ClaudeBar

/// *Share my rank*'s image: posted where its shape fits, so it must come out
/// at exactly that shape's pixels, in whichever theme the member wears.
@Suite
@MainActor
struct RankCardImageTests {
    private let card = RankCard(
        standing: Standing(rank: 8, username: "tokenwhale", total: 3_820_000_000, byProvider: ["claude": 3, "codex": 1]),
        in: BoardView(period: .sevenDays),
        board: (1...34).map { Standing(rank: $0, username: "m\($0)", total: 1) })!

    /// The built-in themes, the ones registered at launch.
    nonisolated static let themes = ["light", "dark", "system", "cli", "christmas", "pop", "platformer"]

    @Test(arguments: RankCard.Shape.allCases, Self.themes)
    func `should come out at the pixels its shape is posted at, in every theme`(shape: RankCard.Shape, themeId: String) throws {
        let theme = try #require(ThemeRegistry.shared.theme(for: themeId))
        let image = RankCardImage(card: card, shape: shape, name: "@tokenwhale", providerName: { $0.capitalized },
                                  theme: theme, colorScheme: themeId == "dark" || themeId == "cli" ? .dark : .light)
        let png = try #require(image.png())
        let bitmap = try #require(NSBitmapImageRep(data: png))

        #expect(CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh) == shape.pixels)

        // RANK_CARD_DUMP=<folder> (as TEST_RUNNER_RANK_CARD_DUMP) writes the images, for a visual check.
        if let folder = ProcessInfo.processInfo.environment["RANK_CARD_DUMP"] {
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("rank-\(themeId)-\(shape.rawValue).png"))
        }
    }
}
