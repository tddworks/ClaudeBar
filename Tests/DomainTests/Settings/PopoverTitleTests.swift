import Testing
@testable import Domain

@Suite
struct PopoverTitleTests {

    @Test
    func `should say ClaudeBar when the person never named it`() {
        #expect(PopoverTitle("").shown == "ClaudeBar")
        #expect(PopoverTitle("").isDefault)
    }

    @Test
    func `should say ClaudeBar when the name is only spaces`() {
        #expect(PopoverTitle("   \n ").shown == "ClaudeBar")
        #expect(PopoverTitle("   \n ").isDefault)
    }

    @Test
    func `should show the person's name without the spaces around it`() {
        let title = PopoverTitle("  Acme AI Desk  ")
        #expect(title.shown == "Acme AI Desk")
        #expect(!title.isDefault)
    }

    @Test
    func `should keep the name on one line when it was typed on several`() {
        #expect(PopoverTitle("Acme\nAI\r\nDesk").shown == "Acme AI Desk")
    }

    @Test
    func `should show only the first 24 characters of a long name`() {
        let title = PopoverTitle("The Very Long Team Name For Our Quotas")
        #expect(title.shown == "The Very Long Team Name")
        #expect(PopoverTitle(String(repeating: "x", count: 30)).shown.count == 24)
    }

    @Test
    func `should keep what the person typed as typed`() {
        #expect(PopoverTitle("  Acme  ").typed == "  Acme  ")
    }
}
