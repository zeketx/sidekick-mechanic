import XCTest
@testable import SidekickCore

final class OnboardingTests: XCTestCase {
    func testWelcomeStatesChatFirstMechanicAndOneTruck() {
        XCTAssertEqual(OnboardingCopy.welcomeTitle, "Your mechanic. One truck.")
        XCTAssertTrue(OnboardingCopy.welcomeBody.contains("chat"))
        XCTAssertEqual(OnboardingCopy.truckName, "1990 Land Cruiser LJ78")
        XCTAssertEqual(OnboardingCopy.truckMeta, "2JZ-GE swap · no turbo · donor year TBD")
        XCTAssertEqual(OnboardingCopy.bayCaption, "Engine bay photo")
    }

    func testHowItWorksUsesFixtureCitationChip() {
        XCTAssertEqual(OnboardingCopy.steps.map(\.title), [
            "1. Chat",
            "2. Cited answer",
            "3. Outline on a photo",
        ])
        XCTAssertEqual(OnboardingCopy.citationExample, "FAKE-DOC-2JZ · p. 999")
        XCTAssertTrue(OnboardingCopy.steps[1].body.contains(OnboardingCopy.citationExample))
    }

    func testGarageConfirmedRowsMatchTruckRegistry() {
        XCTAssertEqual(GarageFacts.confirmed.map(\.label), ["Chassis", "Engine", "Donor ECU"])
        XCTAssertEqual(GarageFacts.confirmed.map(\.value), [
            "1990 Land Cruiser LJ78",
            "2JZ-GE swap",
            "Lexus · year TBD",
        ])
        XCTAssertTrue(GarageFacts.confirmed.allSatisfy(\.isConfirmed))
    }

    func testGaragePendingRowsAreTBD() {
        XCTAssertEqual(GarageFacts.pending.map(\.label), [
            "OBD type",
            "Harness",
            "Photo angles",
        ])
        XCTAssertEqual(GarageFacts.pending.map(\.value), ["TBD", "TBD", "TBD"])
        XCTAssertFalse(GarageFacts.pending.contains { $0.label == "Donor year" })
        XCTAssertTrue(GarageFacts.pending.allSatisfy { !$0.isConfirmed })
        XCTAssertEqual(
            GarageFacts.tbdNotice,
            "Nothing is filled in from memory. TBD stays TBD until it is confirmed in TRUCK.md."
        )
    }

    func testGarageRowsHaveNoSpecFields() {
        let values = (GarageFacts.confirmed + GarageFacts.pending).map(\.value).joined(separator: " ")
        XCTAssertFalse(values.contains("FAKE-SPEC"))
        XCTAssertFalse(values.contains("N·m"))
        XCTAssertFalse(values.contains("pinout"))
        XCTAssertFalse(values.contains("89661-"))
    }

    func testPageOrderAndLaunchRawValues() {
        XCTAssertEqual(OnboardingPage.welcome.rawValue, "onboarding-1")
        XCTAssertEqual(OnboardingPage.howItWorks.rawValue, "onboarding-2")
        XCTAssertEqual(OnboardingPage.garage.rawValue, "onboarding-3")
        XCTAssertEqual(OnboardingPage.welcome.next, .howItWorks)
        XCTAssertEqual(OnboardingPage.howItWorks.next, .garage)
        XCTAssertNil(OnboardingPage.garage.next)
    }

    func testResetAndScreenLaunchArguments() {
        let launch = OnboardingLaunchOptions.parse(
            arguments: [
                "SidekickMechanic",
                "-resetOnboarding",
                "-screen",
                "onboarding-2",
            ],
            environment: [:]
        )
        XCTAssertTrue(launch.resetOnboarding)
        XCTAssertEqual(launch.screen, .howItWorks)
        XCTAssertTrue(launch.showsOnboarding)
    }

    func testScreenArgumentOpensEachPage() {
        for page in OnboardingPage.allCases {
            let launch = OnboardingLaunchOptions.parse(
                arguments: ["SidekickMechanic", "-screen", page.rawValue],
                environment: [:]
            )
            XCTAssertEqual(launch.screen, page)
            XCTAssertFalse(launch.resetOnboarding)
            XCTAssertTrue(launch.showsOnboarding)
        }
    }

    func testUnknownScreenIsIgnored() {
        let launch = OnboardingLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "onboarding-4"],
            environment: [:]
        )
        XCTAssertNil(launch.screen)
        XCTAssertFalse(launch.showsOnboarding)
    }

    func testEmptyLaunchLeavesOnboardingAlone() {
        let launch = OnboardingLaunchOptions.parse(
            arguments: ["SidekickMechanic"],
            environment: [:]
        )
        XCTAssertFalse(launch.resetOnboarding)
        XCTAssertNil(launch.screen)
        XCTAssertFalse(launch.showsOnboarding)
    }

    func testLaunchEnvironmentHooksMatchArguments() {
        let launch = OnboardingLaunchOptions.parse(
            arguments: ["SidekickMechanic"],
            environment: [
                "SIDEKICK_RESET_ONBOARDING": "1",
                "SIDEKICK_SCREEN": "onboarding-3",
            ]
        )
        XCTAssertTrue(launch.resetOnboarding)
        XCTAssertEqual(launch.screen, .garage)
    }

    func testCompletedStorageKeyIsStable() {
        XCTAssertEqual(OnboardingStorage.completedKey, "sidekick.onboarding.completed")
    }
}
