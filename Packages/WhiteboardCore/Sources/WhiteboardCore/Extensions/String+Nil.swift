import Foundation

public extension Optional where Wrapped == String {
    /// `true` when the optional is `nil`.
    var isNil: Bool {
        self == nil
    }

    /// `true` when the optional holds a non-empty string.
    var isNotNilNorEmpty: Bool {
        self?.isEmpty == false
    }

    /// `true` when the optional is `nil` or holds an empty string.
    var isNilOrEmpty: Bool {
        self?.isEmpty != false
    }
}
