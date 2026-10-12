import Foundation
import Observation

/// Which job is on screen, plus the composer and demo settings.
///
/// Messages, loading, and errors are read from `JobsModel` for that job.
@MainActor
@Observable
public final class ChatViewModel {
    public private(set) var target: ChatTarget
    public var composerText: String
    public var isDemoMode: Bool
    public var selectedDemoPhotoID: String?
    public var highlightStyle: DemoHighlightStyle
    public private(set) var confirmDecisions: [String: DemoConfirmDecision]

    @ObservationIgnored private let jobs: JobsModel

    public init(
        jobs: JobsModel,
        target: ChatTarget = .newJob,
        composerText: String = "",
        isDemoMode: Bool = false,
        selectedDemoPhotoID: String? = nil,
        highlightStyle: DemoHighlightStyle = .outline
    ) {
        self.jobs = jobs
        self.target = target
        self.composerText = composerText
        self.isDemoMode = isDemoMode
        self.selectedDemoPhotoID = selectedDemoPhotoID
        self.highlightStyle = highlightStyle
        self.confirmDecisions = [:]
    }

    /// The on-screen job, or nil for a new job or a target that no longer exists.
    public var job: JobSheetState? { target.jobID.flatMap(jobs.job) }

    /// The on-screen job when it has an answer to show on the sheet.
    public var sheetJob: JobSheetState? { job.flatMap { $0.showsSheet ? $0 : nil } }

    public var messages: [Message] { job?.conversation.messages ?? [] }

    public var isLoading: Bool {
        guard let id = target.jobID else { return false }
        return jobs.reply(in: id) == .waiting
    }

    /// A failed save first, then this job's failed reply.
    public var errorMessage: String? {
        if let saveFailure = jobs.saveFailure { return saveFailure }
        guard let id = target.jobID else { return nil }
        if case let .failed(message) = jobs.reply(in: id) { return message }
        return nil
    }

    public var activeDemoPhotoID: String? {
        isDemoMode ? selectedDemoPhotoID : nil
    }

    public var replyOptions: ReplyOptions {
        ReplyOptions(demoPhotoID: activeDemoPhotoID)
    }

    public var canSend: Bool {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, jobs.canAppend(to: target) else { return false }
        if isDemoMode { return selectedDemoPhotoID != nil }
        return true
    }

    /// Writes the trimmed composer into the on-screen job, or a new one, then waits for that reply.
    ///
    /// The user turn is stored before the reply. A failed reply keeps it. An empty composer does not send.
    /// Cancelling this call cancels the reply and does not present a backend failure.
    public func send() async {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        let id: JobID
        do {
            guard let written = try jobs.append(.typed(trimmed), to: target, options: replyOptions) else {
                return
            }
            id = written
        } catch {
            return
        }
        target = .job(id)
        composerText = ""
        await jobs.waitForReply(in: id)
    }

    /// Blank chat. The next send creates a job. Keeps any text already in the composer.
    public func startNewJob() {
        target = .newJob
    }

    /// Shows that job's chat. Ignores an unknown id.
    public func open(_ id: JobID) {
        guard jobs.job(id) != nil else { return }
        target = .job(id)
    }

    public func applyDemoConfirm(messageID: MessageID, decision: DemoConfirmDecision) {
        confirmDecisions[messageID.rawValue] = decision
    }

    public func effectiveDisplay(for messageID: MessageID, highlight: HighlightRef?) -> HighlightDisplay? {
        if let decision = confirmDecisions[messageID.rawValue] {
            switch decision {
            case .yes:
                return .outline
            case .notThis:
                return nil
            }
        }
        return highlight?.display ?? (highlight == nil ? nil : .outline)
    }

    static let unknownFailureMessage = "Something went wrong. Try again."
}

/// Pill radius for the chat composer field. Always half the field height (a Capsule).
public enum ComposerLayout {
    /// Single-line fields land near this; multiline must still use height/2.
    public static let maxCornerRadius: Double = 22
    /// Fitted radius / half-height must stay at or above this (verify-sidekick).
    public static let pillRatioMinimum: Double = 0.75

    public static func cornerRadius(height: Double) -> Double {
        max(height, 0) / 2
    }
}
