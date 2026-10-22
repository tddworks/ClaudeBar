import Providers
import Testing

/// Alibaba's face: its logo in the asset catalog, a cloud symbol where no
/// image renders, and the brand orange behind it.
@MainActor @Suite
struct AlibabaDefinitionTests {
    @Test
    func `should wear Alibaba Cloud's logo, not the question mark`() throws {
        let look = try ProviderFactory.builtIn("alibaba").profile.look
        #expect(look.icon == "AlibabaIcon")
        #expect(look.symbol == "cloud.fill")
        #expect(look.color != nil)
        #expect(look.gradientEnd != nil)
    }
}
