import ClaudeBarKit
import Foundation

// Values cross, exceptions don't (MODULAR_DESIGN §5): a Kotlin command that can fail answers
// with an `Outcome`. Swift code that wants `try` reads it through `value(of:)`.

/// A command Kotlin refused, with the words a screen prints.
public struct KitRefusal: LocalizedError, Sendable, Equatable {
    public let reason: String

    public var errorDescription: String? { reason }
}

/// The command's value when it was done; throws ``KitRefusal`` when it was refused.
/// (A free function: a Swift extension of a generic Kotlin class can't reach its type parameter.)
@discardableResult
public func value<T>(of outcome: Outcome<T>) throws -> T? {
    if let reason = outcome.refusalOrNull { throw KitRefusal(reason: reason) }
    return outcome.valueOrNull
}

extension Outcome: @retroactive @unchecked Sendable {}
