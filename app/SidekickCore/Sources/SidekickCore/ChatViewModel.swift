import Foundation
import Observation

/// Which job is on screen, plus the composer and demo settings.
///
/// Messages, loading, and errors are read from `JobsModel` for that job.
/// `JobsModel` is the only caller of `ChatClient.send`.
@MainActor
@Observable
public final class ChatViewModel {
    public private(set) var target: ChatTarget
    public var composerText: String
    public var isDemoMode: Bool
    public var selectedDemoPhotoID: String?
    public var highlightStyle: DemoHighlightStyle
    public private(set) var confirmDecisions: [String: DemoConfirmDecision]
    /// The page pinned to the composer, and a staged plug photo. The page stays pinned across sends.
    public private(set) var draftAttachment: TurnAttachment?

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

    /// Offered while a page is pinned, no photo is staged, the composer is empty, and a turn can be written.
    public var starterQuestions: [StarterQuestion] {
        guard case .page = draftAttachment,
              jobs.canAppend(to: target),
              composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }
        return StarterQuestion.allCases
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
        if isDemoMode, draftAttachment == nil { return selectedDemoPhotoID != nil }
        return true
    }

    /// Pins `page` to the composer of the on-screen job. A staged photo moves with it.
    public func askAbout(_ page: PageRef) {
        if let photo = draftAttachment?.plugPhoto {
            draftAttachment = .plugPhoto(photo, page: page)
        } else {
            draftAttachment = .page(page)
        }
    }

    public func unpinPage() {
        draftAttachment = nil
    }

    /// Needs a pinned page. Fills in the connector question when the composer is empty.
    public func attachPlugPhoto(_ photo: PlugPhoto) {
        guard let page = draftAttachment?.page else { return }
        draftAttachment = .plugPhoto(photo, page: page)
        if composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            composerText = StarterQuestion.whichConnector.text
        }
    }

    public func removePlugPhoto() {
        guard let page = draftAttachment?.page else { return }
        draftAttachment = .page(page)
    }

    /// Sends the starter's text with the pinned page. Ignored when the starter is not offered.
    public func send(_ starter: StarterQuestion) async {
        guard starterQuestions.contains(starter) else { return }
        composerText = starter.text
        await send()
    }

    /// Writes the trimmed composer into the on-screen job, or a new one, then waits for that reply.
    ///
    /// A pinned page goes through `append(.page)`, including a staged plug photo.
    /// Each of those turns carries the page. A sent photo is used up; the page stays pinned.
    /// A typed turn with no pin goes through `append(.typed)`.
    /// The user turn is stored before the reply. A failed reply keeps it. An empty composer does not send.
    /// Cancelling this call cancels the reply and does not present a backend failure.
    public func send() async {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        let attachment = draftAttachment
        let id: JobID
        do {
            let written = try append(trimmed, attachment: attachment)
            guard let written else { return }
            id = written
        } catch {
            return
        }
        if let attachment {
            draftAttachment = .page(attachment.page)
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

    /// Page turns omit the demo bay photo. The server answers from the page.
    private func append(_ text: String, attachment: TurnAttachment?) throws -> JobID? {
        guard let attachment else {
            return try jobs.append(.typed(text), to: target, options: replyOptions)
        }
        guard let messageID = jobs.makeMessageID() else { return nil }
        // PageAsk stores a citation. The wire sends doc id and page only, so the snippet is the chip.
        guard let citation = Citation(
            docID: attachment.page.docID,
            page: attachment.page.page,
            snippet: attachment.page.chipLabel
        ) else { return nil }
        let ask = PageAsk(
            messageID: messageID,
            citation: citation,
            question: text,
            plugPhoto: attachment.plugPhoto
        )
        return try jobs.append(.page(ask), to: target, options: .none)
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
