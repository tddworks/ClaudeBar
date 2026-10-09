import Foundation
import Mockable

/// The titles a Claude Code session's transcript holds: the name the person
/// gave it with `/rename`, and the title Claude Code wrote for it. Either is
/// nil until the transcript has one.
public struct TranscriptTitles: Sendable, Equatable, Codable {
    /// The name given with `/rename`, if any.
    public let named: String?
    /// The title Claude Code wrote for the session, if any.
    public let generated: String?

    /// Titles as found; pass nil for one the transcript doesn't hold.
    public init(named: String?, generated: String?) {
        self.named = named
        self.generated = generated
    }
}

/// Reads a session's titles from the transcript its hook events point at.
@Mockable
public protocol SessionTitles: Sendable {
    /// The latest name and the latest Claude Code title in the transcript at
    /// `path`; both nil when it has neither or can't be read.
    func read(transcriptAt path: String) async -> TranscriptTitles
}
