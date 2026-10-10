#if os(macOS)
import Testing
@testable import Leaderboard

/// The Mac's model as a device's label (design §6): the product name on Apple
/// silicon, an Intel Mac's family, "Mac" when neither can be read, and never
/// the computer's name, which this reads nothing of.
@Suite
struct MacModelTests {
    @Test func `should name an Apple silicon Mac by its product name, without the parenthetical`() {
        #expect(MacModel.name(productName: "MacBook Pro (14-inch, 2021)", identifier: "MacBookPro18,3") == "MacBook Pro")
        #expect(MacModel.name(productName: "Mac mini (2023)", identifier: "Mac14,3") == "Mac mini")
    }

    @Test(arguments: [
        ("MacBookPro16,1", "MacBook Pro"), ("MacBookAir9,1", "MacBook Air"), ("MacBook10,1", "MacBook"),
        ("Macmini8,1", "Mac mini"), ("iMac20,1", "iMac"), ("iMacPro1,1", "iMac Pro"), ("MacPro7,1", "Mac Pro"),
    ])
    func `should name an Intel Mac by its family`(identifier: String, name: String) {
        #expect(MacModel.name(productName: nil, identifier: identifier) == name)
    }

    @Test func `should call the Mac "Mac" when neither its product name nor its family can be read`() {
        #expect(MacModel.name(productName: nil, identifier: nil) == "Mac")
        #expect(MacModel.name(productName: "  ", identifier: "VirtualMac2,1") == "Mac")
    }
}
#endif
