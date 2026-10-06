import Foundation

/// AppStorage / UserDefaults key. After Skip or Finish, first-open screens stay off.
public enum OnboardingStorage {
    public static let completedKey = "sidekick.onboarding.completed"
}

/// First-open pages. Raw values match `-screen` launch arguments.
public enum OnboardingPage: String, CaseIterable, Equatable, Sendable {
    case welcome = "onboarding-1"
    case howItWorks = "onboarding-2"
    case garage = "onboarding-3"

    public var next: OnboardingPage? {
        switch self {
        case .welcome: .howItWorks
        case .howItWorks: .garage
        case .garage: nil
        }
    }
}

/// Launch arguments for first-open screenshots. No typing required.
///
/// `-resetOnboarding -screen onboarding-1|onboarding-2|onboarding-3`
/// Env: `SIDEKICK_RESET_ONBOARDING`, `SIDEKICK_SCREEN`.
public struct OnboardingLaunchOptions: Equatable, Sendable {
    public var resetOnboarding: Bool
    public var screen: OnboardingPage?

    public init(resetOnboarding: Bool = false, screen: OnboardingPage? = nil) {
        self.resetOnboarding = resetOnboarding
        self.screen = screen
    }

    public static func parse(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> OnboardingLaunchOptions {
        let reset = arguments.contains("-resetOnboarding")
            || truthy(environment["SIDEKICK_RESET_ONBOARDING"])
        let raw = flag(arguments, "-screen") ?? environment["SIDEKICK_SCREEN"]
        return OnboardingLaunchOptions(
            resetOnboarding: reset,
            screen: raw.flatMap(OnboardingPage.init(rawValue:))
        )
    }

    public var showsOnboarding: Bool {
        resetOnboarding || screen != nil
    }

    private static func flag(_ arguments: [String], _ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return nil }
        let value = arguments[next]
        return value.hasPrefix("-") ? nil : value
    }

    private static func truthy(_ raw: String?) -> Bool {
        switch raw?.lowercased() {
        case "1", "true", "yes": true
        default: false
        }
    }
}

/// One garage row. Display only. Values are from `docs/vehicle/TRUCK.md`.
public struct GarageFact: Equatable, Identifiable, Hashable, Sendable {
    public var id: String { label }
    public let label: String
    public let value: String
    public let isConfirmed: Bool
}

/// Confirmed truck facts and TBD rows. No input fields.
public enum GarageFacts {
    /// Chassis, engine, donor ECU — confirmed in TRUCK.md (2026-09-30, VISION.md / AGENTS.md).
    public static let confirmed: [GarageFact] = [
        GarageFact(label: "Chassis", value: "1990 Land Cruiser LJ78", isConfirmed: true),
        GarageFact(label: "Engine", value: "2JZ-GE swap", isConfirmed: true),
        GarageFact(label: "Donor ECU", value: "Lexus donor ECU", isConfirmed: true),
    ]

    /// Donor year, OBD type, harness, photo angles — TBD in TRUCK.md until delivery.
    public static let pending: [GarageFact] = [
        GarageFact(label: "Donor year", value: "TBD", isConfirmed: false),
        GarageFact(label: "OBD type", value: "TBD", isConfirmed: false),
        GarageFact(label: "Harness", value: "TBD", isConfirmed: false),
        GarageFact(label: "Photo angles", value: "TBD", isConfirmed: false),
    ]

    public static let tbdNotice =
        "Nothing is filled in from memory. TBD stays TBD until it is confirmed in TRUCK.md."
}

public struct OnboardingStep: Equatable, Hashable, Sendable {
    public let title: String
    public let body: String
}

/// First-open copy. Screen 2 citation example is the fixture chip, not a real page.
public enum OnboardingCopy {
    public static let welcomeTitle = "Your mechanic. One truck."
    public static let welcomeBody =
        "Ask about a problem in chat. Sidekick answers from the manuals, with the page, and shows the part on a photo."
    public static let truckName = "1990 Land Cruiser LJ78"
    public static let truckMeta = "2JZ-GE swap · no turbo · donor year TBD"

    public static let howItWorksTitle = "Three things, every time"
    public static let steps: [OnboardingStep] = [
        OnboardingStep(
            title: "1. Chat",
            body: "Describe the problem in your own words. You do not need part names."
        ),
        OnboardingStep(
            title: "2. Cited answer",
            body: "A short reply plus a chip like FAKE-DOC-2JZ · p. 999. Tap it to see that page."
        ),
        OnboardingStep(
            title: "3. Outline on a photo",
            body: "A line around the part. If your photo is new, the line goes on a labeled reference photo instead."
        ),
    ]

    public static let garageTitle = "Known facts only"
    public static let citationExample = "FAKE-DOC-2JZ · p. 999"
}
