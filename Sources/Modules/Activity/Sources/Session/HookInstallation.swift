import Foundation
import Mockable

/// Claude Code's hooks in `~/.claude/settings.json`: whether ClaudeBar's are
/// there, and putting them in or taking them out (the Hooks pane's switch).
@Mockable
public protocol HookInstallation: Sendable {
    var isInstalled: Bool { get }
    func install() throws
    func uninstall() throws
}
