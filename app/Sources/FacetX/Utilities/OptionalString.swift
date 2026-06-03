import Foundation

extension Optional where Wrapped == String {
    /// The wrapped string when it is non-nil and non-empty, otherwise nil.
    /// Lets callers collapse "use the saved value, else fall back" into one
    /// `?? default` expression.
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
