import Foundation

/// *Hide account email* (#375): an email shows as `s•••@g•••.com` — enough to
/// tell two logins apart, not enough to read off a screen share. Anything
/// that isn't an email (a name the person gave a login) is left as it is.
enum AccountEmailMask {
    private static let email = try! NSRegularExpression(pattern: #"([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9-])[A-Za-z0-9.-]*\.([A-Za-z]{2,})"#)

    static func masked(_ text: String) -> String {
        email.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1•••@$2•••.$3")
    }
}

extension AppSettings {
    /// A login's name as the popover and menu bar print it: masked when
    /// *Hide account email* is on.
    func shown(_ name: String) -> String {
        hideAccountEmail ? AccountEmailMask.masked(name) : name
    }
}
