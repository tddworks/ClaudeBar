import Foundation

/// A file saved whole and at once: the new contents go to a new file beside
/// it, which then takes its name, so whoever reads it meanwhile (the CLI that
/// owns a login file, a shell, another ClaudeBar process) finds the old
/// contents or the new, never part of either. Every file the modules save goes
/// through `write(_:to:)`, which each platform defines once: on the Mac and
/// Linux Foundation's atomic write, on Windows its own (`AtomicFile+Windows`),
/// since Foundation's can lose the save there.
public enum AtomicFile {}
