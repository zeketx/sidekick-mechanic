import Foundation
import Observation

/// Sheet height. Full is a detent only — steps, notes, and tags stay in #97.
public enum JobSheetDetent: String, CaseIterable, Hashable, Sendable {
    case collapsed
    case half
    case full

    public var nextUp: JobSheetDetent? {
        switch self {
        case .collapsed: .half
        case .half: .full
        case .full: nil
        }
    }

    public var nextDown: JobSheetDetent? {
        switch self {
        case .full: .half
        case .half: .collapsed
        case .collapsed: nil
        }
    }

    public var blocksChat: Bool { self != .collapsed }
}

/// Close-out. Exactly one value once Zeke picks.
public enum JobOutcome: String, CaseIterable, Hashable, Sendable {
    case worked
    case partly
    case didnt

    public var label: String {
        switch self {
        case .worked: "Worked"
        case .partly: "Partly"
        case .didnt: "Didn't"
        }
    }
}

/// Launch keys for the job sheet. Matches the Figma frame names.
public enum JobSheetScreen: String, CaseIterable, Hashable, Sendable {
    case collapsed = "job-sheet-collapsed"
    case half = "job-sheet-half"
    case full = "job-sheet-full"
    case closeout = "job-sheet-closeout"

    public var detent: JobSheetDetent {
        switch self {
        case .collapsed: .collapsed
        case .half, .closeout: .half
        case .full: .full
        }
    }

    public var outcome: JobOutcome? {
        self == .closeout ? .worked : nil
    }
}

/// Copy locked by tests. Fixture citation only — no vehicle specs.
public enum JobSheetCopy {
    public static let title = "Cold idle"
    public static let titlePrefix = "Job · "
    public static let open = "Open"
    public static let close = "Close"
    public static let attach = "Attach a photo"
    public static let attachHint = "Demo bay photo. Not Zeke's truck."
    public static let photoCaption = "Engine bay photo"
    public static let peekHint = "Photo + outline sit here"
    public static let outcomeHeading = "Outcome"
    public static let question = "Rough idle after a cold start"
    public static let answer =
        "Start with the air box on top. FAKE-DOC-2JZ p. 999. No guessed numbers."
    public static let chip = "FAKE-DOC-2JZ · p. 999"
}

/// One job. Photo is this job's attach, not a bay-map frame.
public struct JobSheetState: Equatable, Sendable, Identifiable {
    public var id: MessageID { sourceMessageID }
    public var sourceMessageID: MessageID
    public var title: String
    public var answerText: String
    public var citations: [Citation]
    public var photoID: String?
    public var highlight: HighlightRef?
    public var detent: JobSheetDetent
    public var outcome: JobOutcome?

    public var hasPhoto: Bool { photoID != nil }
    public var headerTitle: String { JobSheetCopy.titlePrefix + title }
    public var blocksChat: Bool { detent.blocksChat }

    public init(
        sourceMessageID: MessageID,
        title: String,
        answerText: String,
        citations: [Citation] = [],
        photoID: String? = nil,
        highlight: HighlightRef? = nil,
        detent: JobSheetDetent = .collapsed,
        outcome: JobOutcome? = nil
    ) {
        self.sourceMessageID = sourceMessageID
        self.title = title
        self.answerText = answerText
        self.citations = citations
        self.photoID = photoID
        self.highlight = highlight
        self.detent = detent
        self.outcome = outcome
    }
}

/// Scripted Cold idle job. Same demo data as #93 / #112.
public enum JobSheetScript {
    public static let userMessageID = MessageID(rawValue: "job-sheet-user")!
    public static let assistantMessageID = MessageID(rawValue: "job-sheet-assistant")!
    public static let partID = PartID(rawValue: "fake-part-intake")!

    public static func highlight(photoID: String) -> HighlightRef {
        HighlightRef(
            bayPhotoID: BayPhotoID(rawValue: photoID) ?? BayPhotoID(rawValue: "fake-bay-photo-front")!,
            partID: partID,
            display: .outline,
            geometry: HighlightViewerScript.airBoxGeometry,
            isDemo: true
        )
    }

    public static var messages: [Message] {
        [
            .user(UserMessage(id: userMessageID, text: JobSheetCopy.question)!),
            .assistant(AssistantMessage(id: assistantMessageID, answer: answer)),
        ]
    }

    public static var answer: Answer {
        .found(
            FoundAnswer(
                text: JobSheetCopy.answer,
                citations: [HighlightViewerScript.fixtureCitation],
                highlight: highlight(photoID: DemoLaunchOptions.defaultPhotoID)
            )!
        )
    }

    public static func makeJob(
        detent: JobSheetDetent,
        photoID: String?,
        outcome: JobOutcome? = nil
    ) -> JobSheetState {
        JobSheetState(
            sourceMessageID: assistantMessageID,
            title: JobSheetCopy.title,
            answerText: JobSheetCopy.answer,
            citations: [HighlightViewerScript.fixtureCitation],
            photoID: photoID,
            highlight: photoID.map(highlight),
            detent: detent,
            outcome: outcome
        )
    }
}

/// Session-only job sheet. Not persisted.
@MainActor
@Observable
public final class JobSheetViewModel {
    public var job: JobSheetState?

    public var detent: JobSheetDetent { job?.detent ?? .collapsed }
    public var blocksChat: Bool { job?.blocksChat ?? false }
    public var hasJob: Bool { job != nil }

    public init(job: JobSheetState? = nil) {
        self.job = job
    }

    public func applyLaunch(_ screen: JobSheetScreen, photoID: String) {
        job = JobSheetScript.makeJob(
            detent: screen.detent,
            photoID: photoID,
            outcome: screen.outcome
        )
    }

    public func sync(from messages: [Message], photoID: String?) {
        guard let assistant = Self.latestAssistant(in: messages) else { return }
        if job?.sourceMessageID == assistant.id { return }
        let highlight = Self.highlight(from: assistant.answer) ?? photoID.map(JobSheetScript.highlight)
        job = JobSheetState(
            sourceMessageID: assistant.id,
            title: Self.title(from: messages),
            answerText: assistant.answer.text,
            citations: Self.citations(from: assistant.answer),
            photoID: photoID ?? highlight?.bayPhotoID.rawValue,
            highlight: highlight,
            detent: .collapsed,
            outcome: nil
        )
    }

    public func open() {
        setDetent(.half)
    }

    public func close() {
        setDetent(.collapsed)
    }

    public func setDetent(_ detent: JobSheetDetent) {
        update { $0.detent = detent }
    }

    public func expand() {
        if let next = detent.nextUp { setDetent(next) }
    }

    public func collapseStep() {
        if let next = detent.nextDown { setDetent(next) }
    }

    public func applyDrag(translationHeight: Double) {
        if translationHeight < -40 {
            expand()
        } else if translationHeight > 40 {
            collapseStep()
        }
    }

    public func selectOutcome(_ outcome: JobOutcome) {
        update { $0.outcome = outcome }
    }

    /// Binds a photo to this job only. Does not write a bay-map frame.
    public func attachPhoto(photoID: String) {
        update { job in
            job.photoID = photoID
            job.highlight = JobSheetScript.highlight(photoID: photoID)
        }
    }

    private func update(_ body: (inout JobSheetState) -> Void) {
        guard var job else { return }
        body(&job)
        self.job = job
    }

    public static func latestAssistant(in messages: [Message]) -> AssistantMessage? {
        for message in messages.reversed() {
            if case let .assistant(assistant) = message {
                return assistant
            }
        }
        return nil
    }

    public static func title(from messages: [Message]) -> String {
        for message in messages.reversed() {
            if case let .user(user) = message {
                if user.text == JobSheetCopy.question { return JobSheetCopy.title }
                let words = user.text.split(whereSeparator: \.isWhitespace)
                return words.prefix(3).joined(separator: " ")
            }
        }
        return JobSheetCopy.title
    }

    public static func citations(from answer: Answer) -> [Citation] {
        if case let .found(found) = answer {
            return found.citations
        }
        return []
    }

    public static func highlight(from answer: Answer) -> HighlightRef? {
        if case let .found(found) = answer {
            return found.highlight
        }
        return nil
    }
}
