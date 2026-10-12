import Foundation
import XCTest
@testable import SidekickCore

private let jobLaunchNow = Date(timeIntervalSince1970: 1_760_000_000)

@MainActor
final class JobsLaunchTests: XCTestCase {

    func testScreenLaunchIsMemoryAndBeatsTheJobsStoreFlag() {
        let half = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-screen", "job-sheet-half"],
            environment: [:],
            now: jobLaunchNow
        )
        XCTAssertEqual(
            half,
            JobsLaunch(
                source: .memory([
                    JobSheetScript.job(photoID: "commons-hilux-2jz", outcome: nil, now: jobLaunchNow),
                ]),
                opening: .job(JobSheetScript.jobID),
                sheetDetent: .half
            )
        )

        let closeout = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-screen", "job-sheet-closeout"],
            environment: [:],
            now: jobLaunchNow
        )
        XCTAssertEqual(closeout.sheetDetent, .half)
        XCTAssertEqual(closeout.opening, .job(JobSheetScript.jobID))
        if case let .memory(jobs) = closeout.source {
            XCTAssertEqual(jobs.count, 1)
            XCTAssertEqual(jobs[0].outcome, .worked)
            XCTAssertEqual(jobs[0].title, "Cold idle")
        } else {
            XCTFail("closeout should be memory")
        }

        let full = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-screen", "job-sheet-full"],
            environment: [:],
            now: jobLaunchNow
        )
        XCTAssertEqual(full.sheetDetent, .full)
        if case let .memory(jobs) = full.source {
            XCTAssertEqual(jobs[0].outcome, .worked)
        } else {
            XCTFail("full should be memory")
        }

        let citation = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-screen", "citation-page", "-jobsStore", "demo"],
            environment: [:],
            now: jobLaunchNow
        )
        XCTAssertEqual(citation.sheetDetent, .half)
        XCTAssertEqual(citation.opening, .job(JobSheetScript.jobID))
        if case let .memory(jobs) = citation.source {
            XCTAssertEqual(jobs.count, 1)
            XCTAssertNil(jobs[0].outcome)
        } else {
            XCTFail("citation-page should be memory")
        }

        let history = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-screen", "job-history", "-jobsStore", "keep"],
            environment: [:],
            now: jobLaunchNow
        )
        XCTAssertEqual(
            history,
            JobsLaunch(
                source: .memory(JobHistoryScript.jobs(now: jobLaunchNow)),
                opening: .newJob,
                sheetDetent: .collapsed
            )
        )

        let highlight = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-screen", "confident", "-jobsStore", "demo"],
            environment: [:],
            now: jobLaunchNow
        )
        XCTAssertEqual(highlight, JobsLaunch(source: .memory([]), opening: .newJob, sheetDetent: .collapsed))

        let garage = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-screen", "garage"],
            environment: [:],
            now: jobLaunchNow
        )
        XCTAssertEqual(garage.source, .memory([]))
    }

    func testJobsStoreFlagChoosesDemoKeepOrFreshAndNeverApplicationSupport() {
        let demo = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-jobsStore", "demo"],
            environment: [:],
            now: jobLaunchNow
        )
        XCTAssertEqual(
            demo,
            JobsLaunch(
                source: .memory(JobHistoryScript.jobs(now: jobLaunchNow)),
                opening: .newJob,
                sheetDetent: .collapsed
            )
        )

        let keep = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-jobsStore", "keep"],
            environment: [:],
            now: jobLaunchNow
        )
        XCTAssertEqual(keep, JobsLaunch(source: .file(.temporary(.keep)), opening: .newJob, sheetDetent: .collapsed))

        let fromEnvironment = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic"],
            environment: ["SIDEKICK_JOBS_STORE": "keep"],
            now: jobLaunchNow
        )
        XCTAssertEqual(fromEnvironment.source, .file(.temporary(.keep)))

        for value in ["fresh", "1", "true", "typo"] {
            let launch = JobsLaunch.resolve(
                demo: DemoLaunchOptions(),
                arguments: ["SidekickMechanic", "-jobsStore", value],
                environment: [:],
                now: jobLaunchNow
            )
            XCTAssertEqual(
                launch,
                JobsLaunch(source: .file(.temporary(.fresh)), opening: .newJob, sheetDetent: .collapsed),
                value
            )
        }

        let bare = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-jobsStore"],
            environment: [:],
            now: jobLaunchNow
        )
        XCTAssertEqual(bare.source, .file(.temporary(.fresh)))

        let normal = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic"],
            environment: [:],
            now: jobLaunchNow
        )
        XCTAssertEqual(
            normal,
            JobsLaunch(source: .file(.applicationSupport), opening: .newJob, sheetDetent: .collapsed)
        )
    }

    func testScreenPlusFreshInstallsTheScriptedJobInTheTempFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(JobsLaunch.temporaryFolderName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let beforeSupport = applicationSupportJobsURL().flatMap { try? Data(contentsOf: $0) }
        let launch = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-screen", "job-sheet-half", "-jobsStore", "fresh"],
            environment: [:],
            now: jobLaunchNow
        )
        XCTAssertEqual(launch.source, .file(.temporary(.fresh)))
        XCTAssertEqual(launch.opening, .job(JobSheetScript.jobID))
        XCTAssertEqual(launch.sheetDetent, .half)
        XCTAssertEqual(launch.installed.map(\.id), [JobSheetScript.jobID])

        let jobs = JobsModel(
            source: launch.source,
            client: LaunchIdleClient(),
            installing: launch.installed,
            now: { jobLaunchNow }
        )
        XCTAssertEqual(jobs.storage, .saving)
        XCTAssertEqual(jobs.jobs.map(\.id), [JobSheetScript.jobID])
        XCTAssertEqual(jobs.job(JobSheetScript.jobID)?.title, "Cold idle")

        let url = root.appendingPathComponent("jobs.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let kept = JobsModel(source: .file(.temporary(.keep)), client: LaunchIdleClient(), now: { jobLaunchNow })
        XCTAssertEqual(kept.jobs.map(\.id), [JobSheetScript.jobID])
        if let support = applicationSupportJobsURL() {
            XCTAssertEqual(try? Data(contentsOf: support), beforeSupport)
        }
    }

    func testScreenAndDemoStoreDoNotCreateJobsFile() throws {
        let screen = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-screen", "job-history", "-jobsStore", "demo"],
            environment: [:],
            now: jobLaunchNow
        )
        let demo = JobsLaunch.resolve(
            demo: DemoLaunchOptions(),
            arguments: ["SidekickMechanic", "-jobsStore", "demo"],
            environment: [:],
            now: jobLaunchNow
        )
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(JobsLaunch.temporaryFolderName, isDirectory: true)
            .appendingPathComponent("jobs.json")
        let beforeTemporary = try? Data(contentsOf: temporary)
        let support = applicationSupportJobsURL()
        let beforeSupport = support.flatMap { try? Data(contentsOf: $0) }

        for launch in [screen, demo] {
            let jobs = JobsModel(source: launch.source, client: LaunchIdleClient(), now: { jobLaunchNow })
            XCTAssertEqual(jobs.storage, .preview)
            XCTAssertNil(jobs.notice)
            XCTAssertEqual(jobs.jobs.count, 4)
            XCTAssertEqual(jobs.jobs.map(\.title), ["Cold idle", "Hard start", "Battery light", "Hose check"])
        }

        XCTAssertEqual(try? Data(contentsOf: temporary), beforeTemporary)
        if let support {
            XCTAssertEqual(try? Data(contentsOf: support), beforeSupport)
        }
    }

    func testFreshTemporaryStoreWipesAndKeepLeavesANewerFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(JobsLaunch.temporaryFolderName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("jobs.json")
        let newer = Data(#"{"version":2,"jobs":[]}"#.utf8)
        try newer.write(to: url)

        let kept = JobsModel(source: .file(.temporary(.keep)), client: LaunchIdleClient(), now: { jobLaunchNow })
        XCTAssertEqual(kept.storage, .notSaving(.newerVersion(found: 2)))
        XCTAssertEqual(try Data(contentsOf: url), newer)

        let fresh = JobsModel(source: .file(.temporary(.fresh)), client: LaunchIdleClient(), now: { jobLaunchNow })
        XCTAssertEqual(fresh.jobs, [])
        XCTAssertEqual(fresh.storage, .saving)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func applicationSupportJobsURL() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }
        return base
            .appendingPathComponent("SidekickMechanic", isDirectory: true)
            .appendingPathComponent("jobs.json")
    }
}

private struct LaunchIdleClient: ChatClient {
    func send(
        _ conversation: Conversation,
        demoPhotoID: String?,
        garage: GarageChatContext?
    ) async throws -> Answer {
        _ = conversation
        _ = demoPhotoID
        _ = garage
        throw ChatClientError.offline
    }
}
