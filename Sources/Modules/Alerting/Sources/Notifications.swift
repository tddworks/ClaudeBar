import Foundation

/// This Mac's notifications: a destination for every alert, and the person's
/// permission to show them.
public protocol Notifications: AlertDestination {
    func requestPermission() async -> Bool
}
