import Foundation
import Observation

/// Where the next turn goes. `.newJob` creates the job when the first turn is written.
public enum ChatTarget: Hashable, Sendable {
    case newJob
    case job(JobID)

    public var jobID: JobID? {
        if case let .job(id) = self { return id }
        return nil
    }
}

/// What the owner asked. Both cases become a `UserMessage`.
/// A page turn keeps this text and also carries the page on the `/chat` body.
public enum UserTurn: Equatable, Sendable {
    case typed(String)
    case page(PageAsk)

    var messageText: String? {
        switch self {
        case let .typed(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let .page(ask):
            let question = ask.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = "\(question)\n\(ask.citation.docID.rawValue) · p. \(ask.citation.page.rawValue)"
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Page identity for the wire. Nil for a typed turn. Photo bytes ride only with a plug check.
    var attachment: TurnAttachment? {
        switch self {
        case .typed:
            return nil
        case let .page(ask):
            let page = ask.citation.pageRef
            if let photo = ask.plugPhoto {
                return .plugPhoto(photo, page: page)
            }
            return .page(page)
        }
    }
}

/// "Ask about this page". The caller mints `messageID` so a repeat tap is a no-op.
/// `plugPhoto` is set only for the connector check. The stored text stays question plus page.
public struct PageAsk: Equatable, Sendable {
    public var messageID: MessageID
    public var citation: Citation
    public var question: String
    public var plugPhoto: PlugPhoto?

    public init(
        messageID: MessageID,
        citation: Citation,
        question: String,
        plugPhoto: PlugPhoto? = nil
    ) {
        self.messageID = messageID
        self.citation = citation
        self.question = question
        self.plugPhoto = plugPhoto
    }
}

/// The caller-minted page-ask id already belongs to a different job. Nothing was written.
public enum JobAppendError: Error, Equatable, Sendable {
    case messageUsedByAnotherJob(messageID: MessageID, jobID: JobID)
}

/// Request-side settings that are not part of the turn.
public struct ReplyOptions: Equatable, Sendable {
    public var demoPhotoID: String?

    public static let none = ReplyOptions(demoPhotoID: nil)

    public init(demoPhotoID: String?) {
        self.demoPhotoID = demoPhotoID
    }
}

/// One job's reply. In memory only. A relaunch starts every job at `.idle`.
public enum ReplyState: Equatable, Sendable {
    case idle
    case waiting
    case failed(String)
}

public enum JobStorageProblem: Equatable, Sendable {
    /// jobs.json says version N > 1. The bytes stay where they are.
    case newerVersion(found: Int)
    /// jobs.json exists but could not be read. Nothing is moved or written.
    case couldNotRead
    /// jobs.json did not decode and could not be moved aside. Nothing is written.
    case couldNotSetAside
}

/// How this process opened its source. Fixed for the life of the process.
public enum JobStorageStatus: Equatable, Sendable {
    case saving
    case savingAfterSetAside(fileName: String)
    case notSaving(JobStorageProblem)
    case preview

    public var writesToDisk: Bool {
        switch self {
        case .saving, .savingAfterSetAside:
            true
        case .notSaving, .preview:
            false
        }
    }

    public var notice: String? {
        switch self {
        case .saving, .preview:
            nil
        case .savingAfterSetAside:
            JobsCopy.setAside
        case .notSaving(.newerVersion):
            JobsCopy.newerVersion
        case .notSaving(.couldNotRead), .notSaving(.couldNotSetAside):
            JobsCopy.couldNotRead
        }
    }
}

public enum JobsCopy {
    public static let newJob = "New job"
    public static let emptyChat = "Describe a problem."
    public static let emptyList = "No jobs yet. Describe a problem to start one."
    public static let saveFailed = "Could not save this job on this phone."
    public static let replyNotSaved = "The reply came back but could not be saved on this phone. Try again."
    public static let setAside = "Saved jobs could not be opened. A copy was kept on this phone. New jobs save normally."
    public static let newerVersion = "These jobs were saved by a newer version of the app. Update the app to see them. New jobs are not saved until then."
    public static let couldNotRead = "Saved jobs could not be opened right now. Nothing was changed. New jobs are not saved until the app restarts."
}

public enum JobsSource: Equatable, Sendable {
    case file(JobFileLocation)
    /// Never touches disk. Screenshot launches, `-jobsStore demo`, previews, tests.
    case memory([JobSheetState])
}

public enum JobFileLocation: Equatable, Sendable {
    /// Application Support `SidekickMechanic/jobs.json`, next to `Garage/`.
    case applicationSupport
    case temporary(JobsTemporaryMode)
    case directory(URL)
}

/// `fresh` wipes the folder at launch. `keep` does not.
public enum JobsTemporaryMode: String, Equatable, Sendable {
    case fresh
    case keep
}

/// Launch decisions for jobs, so Linux can test them without the app target.
public struct JobsLaunch: Equatable, Sendable {
    public var source: JobsSource
    public var opening: ChatTarget
    public var sheetDetent: JobSheetDetent
    /// Jobs written when `source` is a file that opened empty.
    /// A `-screen` launch stays in memory unless `-jobsStore fresh` is also set.
    public var installed: [JobSheetState] = []

    public static let storeFlag = "-jobsStore"
    public static let storeEnvironmentKey = "SIDEKICK_JOBS_STORE"
    public static let temporaryFolderName = "sidekick-jobs-uitest"

    /// Precedence, first match wins:
    /// 1. `-screen` plus `-jobsStore fresh` installs that screen's jobs into a fresh temp file.
    /// 2. Any other `-screen` / `SIDEKICK_SCREEN` value is memory-only, even with `-jobsStore demo` or `keep`.
    /// 3. `-jobsStore demo` is the four scripted jobs, in memory.
    /// 4. `-jobsStore keep` is the temp file. Any other `-jobsStore` value is a fresh temp file.
    /// 5. Otherwise Application Support, a new job, collapsed.
    public static func resolve(
        demo: DemoLaunchOptions = .parse(),
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()
    ) -> JobsLaunch {
        let rawScreen = LaunchArgument.flag(arguments, "-screen") ?? environment["SIDEKICK_SCREEN"] ?? ""
        if !rawScreen.isEmpty {
            let launched = screenLaunch(rawScreen, demo: demo, now: now)
            if jobsStoreToken(arguments: arguments, environment: environment) == "fresh" {
                return JobsLaunch(
                    source: .file(.temporary(.fresh)),
                    opening: launched.opening,
                    sheetDetent: launched.sheetDetent,
                    installed: launched.memoryJobs
                )
            }
            return launched
        }
        if let token = jobsStoreToken(arguments: arguments, environment: environment) {
            switch token {
            case "demo":
                return JobsLaunch(
                    source: .memory(JobHistoryScript.jobs(now: now)),
                    opening: .newJob,
                    sheetDetent: .collapsed
                )
            case "keep":
                return JobsLaunch(
                    source: .file(.temporary(.keep)),
                    opening: .newJob,
                    sheetDetent: .collapsed
                )
            default:
                return JobsLaunch(
                    source: .file(.temporary(.fresh)),
                    opening: .newJob,
                    sheetDetent: .collapsed
                )
            }
        }
        return JobsLaunch(
            source: .file(.applicationSupport),
            opening: .newJob,
            sheetDetent: .collapsed
        )
    }

    private var memoryJobs: [JobSheetState] {
        if case let .memory(jobs) = source { return jobs }
        return []
    }

    private static func screenLaunch(_ rawScreen: String, demo: DemoLaunchOptions, now: Date) -> JobsLaunch {
        if let screen = JobSheetScreen(rawValue: rawScreen) {
            let job = JobSheetScript.job(
                photoID: demo.resolvedPhotoID,
                outcome: screen.outcome,
                now: now
            )
            return JobsLaunch(
                source: .memory([job]),
                opening: .job(JobSheetScript.jobID),
                sheetDetent: screen.detent
            )
        }
        if CitationPageScreen(rawValue: rawScreen) != nil {
            let job = JobSheetScript.job(photoID: demo.resolvedPhotoID, outcome: nil, now: now)
            return JobsLaunch(
                source: .memory([job]),
                opening: .job(JobSheetScript.jobID),
                sheetDetent: .half
            )
        }
        if rawScreen == LookBackScreen.jobHistory.rawValue {
            return JobsLaunch(
                source: .memory(JobHistoryScript.jobs(now: now)),
                opening: .newJob,
                sheetDetent: .collapsed
            )
        }
        return JobsLaunch(source: .memory([]), opening: .newJob, sheetDetent: .collapsed)
    }

    /// Nil when the flag is absent. `""` when the flag is present with no value.
    private static func jobsStoreToken(arguments: [String], environment: [String: String]) -> String? {
        if let index = arguments.firstIndex(of: storeFlag) {
            let next = arguments.index(after: index)
            if next < arguments.endIndex, !arguments[next].hasPrefix("-") {
                return arguments[next]
            }
            return ""
        }
        return environment[storeEnvironmentKey]
    }
}

/// The one writer of jobs.json, and the one owner of every job's chat.
@MainActor
@Observable
public final class JobsModel {
    /// Newest first.
    public private(set) var jobs: [JobSheetState]
    /// Last failed write. Cleared by the next successful write.
    public private(set) var saveFailure: String?
    private var replies: [JobID: ReplyState] = [:]

    @ObservationIgnored private let backing: Backing
    @ObservationIgnored private var replyTasks: [JobID: Task<Void, Never>] = [:]
    @ObservationIgnored private let client: any ChatClient
    @ObservationIgnored private let makeID: @Sendable () -> String
    @ObservationIgnored private let now: @Sendable () -> Date

    /// A file writer and a memory list cannot be combined. The enum is the only way to hold a writer.
    private enum Backing {
        case file(JobFileWriter, setAsideFileName: String?)
        case memory(MemoryReason)
    }

    private enum MemoryReason {
        case preview
        case blocked(JobStorageProblem)
    }

    /// Opens the source synchronously. A missing file is an empty list and writes nothing.
    /// `installing` is written only when a file source opened empty, so a fresh temp store can hold a screen's jobs.
    public init(
        source: JobsSource,
        client: any ChatClient,
        installing: [JobSheetState] = [],
        makeID: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.makeID = makeID
        self.now = now
        switch source {
        case let .memory(seed):
            jobs = seed
            backing = .memory(.preview)
        case let .file(location):
            switch JobFile.open(location, now: now()) {
            case let .ready(loaded, writer):
                if loaded.isEmpty, !installing.isEmpty {
                    jobs = installing
                    backing = .file(writer, setAsideFileName: nil)
                    do {
                        try writer.save(installing)
                    } catch {
                        jobs = []
                        saveFailure = JobsCopy.saveFailed
                    }
                } else {
                    jobs = loaded
                    backing = .file(writer, setAsideFileName: nil)
                }
            case let .setAside(name, writer):
                jobs = []
                backing = .file(writer, setAsideFileName: name)
            case let .blocked(problem):
                jobs = []
                backing = .memory(.blocked(problem))
            }
        }
    }

    public var storage: JobStorageStatus {
        switch backing {
        case let .file(_, setAside):
            if let setAside {
                return .savingAfterSetAside(fileName: setAside)
            }
            return .saving
        case .memory(.preview):
            return .preview
        case let .memory(.blocked(problem)):
            return .notSaving(problem)
        }
    }

    public var notice: String? {
        saveFailure ?? storage.notice
    }

    public func job(_ id: JobID) -> JobSheetState? {
        jobs.first { $0.id == id }
    }

    public func reply(in id: JobID) -> ReplyState {
        replies[id] ?? .idle
    }

    /// False for an unknown job, or a job that is already waiting. Always true for `.newJob`.
    public func canAppend(to target: ChatTarget) -> Bool {
        switch target {
        case .newJob:
            true
        case let .job(id):
            job(id) != nil && reply(in: id) != .waiting
        }
    }

    /// Writes the owner's turn, then starts this job's reply. The reply lands in the returned job.
    ///
    /// Returns nil and writes nothing when the text is blank, `canAppend` is false, or the write failed.
    /// A page-ask id already in the target job returns that job and does not write.
    /// The same id in a different job throws and does not write.
    @discardableResult
    public func append(_ turn: UserTurn, to target: ChatTarget, options: ReplyOptions) throws -> JobID? {
        let messageID: MessageID
        switch turn {
        case .typed:
            guard let minted = MessageID(rawValue: makeID()) else { return nil }
            messageID = minted
        case let .page(ask):
            messageID = ask.messageID
        }
        if let owner = jobID(containing: messageID) {
            switch target {
            case let .job(id) where id == owner:
                return owner
            case .job, .newJob:
                throw JobAppendError.messageUsedByAnotherJob(messageID: messageID, jobID: owner)
            }
        }
        guard let text = turn.messageText, canAppend(to: target) else { return nil }
        guard let user = UserMessage(id: messageID, text: text, attachment: turn.attachment) else { return nil }
        let id: JobID
        switch target {
        case .newJob:
            guard let minted = JobID(rawValue: makeID()) else { return nil }
            id = minted
            let created = JobSheetState.started(id: id, firstAsk: user, createdAt: now())
            guard commit({ jobs in
                jobs.insert(created, at: 0)
                return true
            }) else { return nil }
        case let .job(existing):
            id = existing
            guard commit({ jobs in
                guard let index = jobs.firstIndex(where: { $0.id == existing }) else { return false }
                jobs[index] = jobs[index].appendingAsk(user)
                return true
            }) else { return nil }
        }
        startReply(for: id, options: options)
        return id
    }

    /// Returns when this job has no reply in flight.
    /// Cancelling the caller cancels that reply. Leaving the screen does not, because the screen does not cancel this call.
    public func waitForReply(in id: JobID) async {
        await withTaskCancellationHandler {
            await replyTasks[id]?.value
        } onCancel: {
            Task { @MainActor in
                self.replyTasks[id]?.cancel()
            }
        }
    }

    /// Next id for a caller-minted page ask. Typed turns mint inside `append`.
    public func makeMessageID() -> MessageID? {
        MessageID(rawValue: makeID())
    }

    /// False when the job is unknown, the edit changes nothing, or the write failed.
    @discardableResult
    public func edit(_ id: JobID, _ edit: JobEdit) -> Bool {
        commit { jobs in
            guard let index = jobs.firstIndex(where: { $0.id == id }),
                  let next = jobs[index].applying(edit)
            else { return false }
            jobs[index] = next
            return true
        }
    }

    private func jobID(containing messageID: MessageID) -> JobID? {
        jobs.first { job in
            job.conversation.messages.contains { $0.id == messageID }
        }?.id
    }

    private func startReply(for id: JobID, options: ReplyOptions) {
        guard let outgoing = job(id)?.conversation else { return }
        replies[id] = .waiting
        let client = self.client
        replyTasks[id] = Task { [client] in
            let result: Result<Answer, any Error>
            do {
                result = .success(try await client.send(outgoing, demoPhotoID: options.demoPhotoID))
            } catch {
                result = .failure(error)
            }
            self.land(result, in: id, options: options)
        }
    }

    private func land(_ result: Result<Answer, any Error>, in id: JobID, options: ReplyOptions) {
        replyTasks[id] = nil
        switch result {
        case let .success(answer):
            guard job(id) != nil else {
                replies[id] = nil
                return
            }
            guard let messageID = MessageID(rawValue: makeID()) else {
                replies[id] = .failed(JobsCopy.replyNotSaved)
                return
            }
            let reply = AssistantMessage(id: messageID, answer: answer)
            let saved = commit { jobs in
                guard let index = jobs.firstIndex(where: { $0.id == id }) else { return false }
                jobs[index] = jobs[index].receiving(reply, demoPhotoID: options.demoPhotoID)
                return true
            }
            replies[id] = saved ? nil : .failed(JobsCopy.replyNotSaved)
        case .failure(is CancellationError):
            replies[id] = nil
        case let .failure(error as ChatClientError):
            replies[id] = .failed(error.userMessage)
        case .failure:
            replies[id] = .failed(ChatViewModel.unknownFailureMessage)
        }
    }

    /// Write first, publish second. A failed write leaves `jobs` as it was.
    private func commit(_ change: (inout [JobSheetState]) -> Bool) -> Bool {
        var next = jobs
        guard change(&next) else { return false }
        if case let .file(writer, _) = backing {
            do {
                try writer.save(next)
            } catch {
                saveFailure = JobsCopy.saveFailed
                return false
            }
        }
        jobs = next
        saveFailure = nil
        return true
    }

    #if DEBUG
    func settleReplies() async {
        let tasks = Array(replyTasks.values)
        for task in tasks {
            await task.value
        }
    }
    #endif
}
