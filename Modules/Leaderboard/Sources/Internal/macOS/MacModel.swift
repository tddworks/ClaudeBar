#if os(macOS)
import Foundation

/// The Mac's model as people read it (design §6): the device tree's
/// `product-name` on Apple silicon ("MacBook Pro (14-inch, 2021)") with the
/// parenthetical dropped; on an Intel Mac, `IOPlatformExpertDevice`'s `model`
/// ("MacBookPro16,1"), its family named ("MacBook Pro"); "Mac" when neither
/// can be read.
enum MacModel {
    private static let families = [
        "MacBookPro": "MacBook Pro", "MacBookAir": "MacBook Air", "MacBook": "MacBook", "Macmini": "Mac mini",
        "iMacPro": "iMac Pro", "iMac": "iMac", "MacPro": "Mac Pro",
    ]

    static func name(productName: String?, identifier: String?) -> String {
        if let productName {
            let name = productName.split(separator: "(", maxSplits: 1).first.map(String.init) ?? ""
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let identifier, let family = families[String(identifier.prefix { !$0.isNumber })] {
            return family
        }
        return "Mac"
    }
}
#endif
