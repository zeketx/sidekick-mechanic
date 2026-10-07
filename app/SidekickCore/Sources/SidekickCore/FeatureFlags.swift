import Foundation

/// Product flags. `unsureHighlight` is internal-only and off in v1 (#87, HL-5).
public struct FeatureFlags: Equatable, Sendable {
    public var unsureHighlight: Bool

    public static let v1 = FeatureFlags(unsureHighlight: false)

    public init(unsureHighlight: Bool = false) {
        self.unsureHighlight = unsureHighlight
    }

    /// `-flagUnsureHighlight 1` or `SIDEKICK_FLAG_UNSURE_HIGHLIGHT=1`.
    public static func parse(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> FeatureFlags {
        let raw = LaunchArgument.flag(arguments, "-flagUnsureHighlight")
            ?? environment["SIDEKICK_FLAG_UNSURE_HIGHLIGHT"]
        return FeatureFlags(unsureHighlight: Self.isEnabled(raw))
    }

    public static func isEnabled(_ raw: String?) -> Bool {
        switch raw?.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}

enum LaunchArgument {
    static func flag(_ arguments: [String], _ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return nil }
        let value = arguments[next]
        return value.hasPrefix("-") ? nil : value
    }
}
