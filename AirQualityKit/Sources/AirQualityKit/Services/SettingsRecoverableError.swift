import Foundation

/// An error the user fixes in the Settings app (for example, denied location access), so the
/// dashboard can offer a direct link instead of a retry that can't succeed.
public protocol SettingsRecoverableError: Error {
    var isRecoverableInSettings: Bool { get }
}
