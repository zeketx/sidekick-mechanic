import Foundation
import Observation

/// Sheet height. Full is edge-to-edge paper; notes, tags, and close-out live in that detent.
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
public enum JobOutcome: String, CaseIterable, Hashable, Sendable, Codable {
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
        switch self {
        case .closeout, .full: .worked
        case .collapsed, .half: nil
        }
    }
}

/// Launch key for the citation sheet (`-screen citation-page`).
public enum CitationPageScreen: String, Hashable, Sendable {
    case page = "citation-page"
}

/// One scripted checkbox on the half sheet. Not the later #97 editor.
public struct JobSheetStep: Equatable, Sendable, Identifiable, Codable {
    public var id: Int
    public var title: String
    public var isComplete: Bool

    public init(id: Int, title: String, isComplete: Bool) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
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
    public static let howDidItGo = "How did it go?"
    public static let notesHeading = "Notes"
    public static let notesPlaceholder = "Hoses look dry. No numbers guessed."
    public static let tagsHeading = "Tags"
    public static let addTag = "+ add"
    public static let addTagPrompt = "Add tag"
    public static let whatFixedPlaceholder = "What fixed it? (optional)"
    public static let question = "Rough idle after a cold start"
    public static let citationNote = "FAKE-DOC-2JZ p. 999. No guessed numbers."
    public static let chip = "FAKE-DOC-2JZ · p. 999"
    public static let stepsHeading = "Steps 1 of 3"
    public static let nextStep = "Next step (from the cited page)"
    public static let creditInfo = "Photo credit"

    /// Same everyday line as #112 for this photo/part, plus the fixture citation.
    public static func answer(
        photoID: String,
        partID: String? = nil,
        state: HighlightViewerState = .confident
    ) -> String {
        let pick = DemoOutlineCatalog.selection(photoID: photoID, partID: partID, state: state)
        return "\(DemoOutlineCatalog.everydayCopy(displayName: pick.displayName, state: state)) \(citationNote)"
    }

    public static var answer: String {
        Self.answer(photoID: DemoLaunchOptions.defaultPhotoID)
    }

    public static func partChip(
        photoID: String,
        partID: String? = nil
    ) -> String {
        let pick = DemoOutlineCatalog.selection(photoID: photoID, partID: partID, state: .confident)
        return DemoOutlineCatalog.shortTag(partID: pick.partID)
    }

    public static func firstStep(displayName: String) -> String {
        "Look at the \(displayName)"
    }

    /// Half-sheet checkboxes from the Figma frame. Third step stays in #97.
    public static func steps(
        photoID: String,
        partID: String? = nil
    ) -> [JobSheetStep] {
        let pick = DemoOutlineCatalog.selection(photoID: photoID, partID: partID, state: .confident)
        return [
            JobSheetStep(id: 1, title: firstStep(displayName: pick.displayName), isComplete: true),
            JobSheetStep(id: 2, title: nextStep, isComplete: false),
        ]
    }

    public static func creditLine(attribution: String, shareAlike: Bool) -> String {
        shareAlike ? "CC BY-SA. \(attribution)" : attribution
    }
}

/// Sheet height vs the window. Full is edge-to-edge paper; header content uses the top inset.
public enum JobSheetLayout {
    public static let collapsedHeight: Double = 128
    public static let halfMaxHeight: Double = 460
    public static let halfHeightFraction: Double = 0.52
    public static let halfPhotoHeight: Double = 72
    public static let halfScrollBottomPadding: Double = 24
    public static let fullPhotoHeight: Double = 200
    public static let fallbackTopSafeArea: Double = 59
    /// Gap of dimmed chat below the island at accessibility half / closeout.
    public static let halfAccessibilityChatSliver: Double = 36
    /// Full paper covers the status-bar band. Header content uses `contentTopInset`.
    public static let fullTopGap: Double = 0
    /// Paper Jobs / Scan log header under the status bar. Full must cover this.
    public static let navigationBarHeight: Double = 44
    /// Edge to edge. Side gutters made the sheet 386pt on a 402pt window.
    public static let horizontalInset: Double = 0
    public static let topCornerRadius: Double = 24
    public static let headerTopClearance: Double = 32
    public static let grabberTopPadding: Double = 8
    public static let grabberHeight: Double = 5
    public static let grabberBottomPadding: Double = 6

    public static var headerPaddingUnderGrabber: Double {
        max(0, headerTopClearance - grabberTopPadding - grabberHeight - grabberBottomPadding)
    }
    /// Space between the last half-sheet step and the Outcome row (Figma divider).
    public static let halfOutcomeTopSpacing: Double = 16
    /// Home-indicator pad inside the white sheet when the overlay ignores the container.
    public static let homeIndicatorContentPad: Double = 16
    /// Tab bar (~49) + home indicator (~34) when `-showDemoChrome 1`.
    public static let demoTabChromeHeight: Double = 83
    /// Overlay home-indicator inset is ~34; keyboard inset is much larger.
    public static let homeIndicatorMaxInset: Double = 80

    public static func resolvedTopSafeArea(_ raw: Double) -> Double {
        raw > 0 ? raw : fallbackTopSafeArea
    }

    /// Darkens chat behind the sheet. Collapsed is undimmed. Half/full stay in the 0.25…0.40 band.
    public static func scrimOpacity(detent: JobSheetDetent) -> Double {
        return switch detent {
        case .collapsed: 0
        case .half: 0.30
        case .full: 0.40
        }
    }

    public static func height(
        detent: JobSheetDetent,
        screenHeight: Double,
        topSafeArea: Double,
        isAccessibilitySize: Bool = false
    ) -> Double {
        return switch detent {
        case .collapsed:
            collapsedHeight
        case .half:
            // Accessibility: grow for wrapped steps, but stay below the island
            // with a real strip of dimmed chat so this still reads as a sheet.
            isAccessibilitySize
                ? max(screenHeight - accessibilityHalfTopGap(topSafeArea: topSafeArea), 240)
                : min(screenHeight * halfHeightFraction, halfMaxHeight)
        case .full:
            // Paper fills the window so the nav / Jobs header cannot peek and
            // there is no gray strip under the sheet. Title + Close sit below
            // the island via `contentTopInset`, not by shortening the sheet.
            max(screenHeight - fullTopGap, 240)
        }
    }

    /// Half photo at default size matches Figma. Accessibility sizes drop it.
    public static func halfPhotoHeight(isAccessibilitySize: Bool) -> Double {
        isAccessibilitySize ? 0 : halfPhotoHeight
    }

    /// Accessibility: Outcome label above full-width segments so Worked is tappable.
    public static func stacksOutcome(isAccessibilitySize: Bool) -> Bool {
        isAccessibilitySize
    }

    /// Status-bar band plus a visible strip of chat above accessibility half paper.
    public static func accessibilityHalfTopGap(topSafeArea: Double) -> Double {
        resolvedTopSafeArea(topSafeArea) + halfAccessibilityChatSliver
    }

    /// Full detent only. Half and collapsed already sit below the status bar.
    public static func contentTopInset(detent: JobSheetDetent, topSafeArea: Double) -> Double {
        detent == .full ? resolvedTopSafeArea(topSafeArea) : 0
    }

    /// Filled Worked/Partly/Didn't segments on full, and on half once an outcome is set (closeout).
    public static func fillsSelectedOutcome(detent: JobSheetDetent, outcome: JobOutcome?) -> Bool {
        detent == .full || (detent == .half && outcome != nil)
    }

    /// Composer sits above the home indicator when there is no job sheet.
    /// Keyboard avoidance is the overlay's job (it must not ignore `.keyboard`).
    public static func composerHomeInset(hasJob: Bool, bottomSafeArea: Double) -> Double {
        if hasJob { return 0 }
        return bottomSafeArea > 0 && bottomSafeArea < homeIndicatorMaxInset ? bottomSafeArea : 0
    }

    /// Full-bleed width. Inset is 0 so this equals `screenWidth`.
    public static func width(screenWidth: Double) -> Double {
        max(screenWidth - 2 * horizontalInset, 0)
    }

    /// Sheets sit on the window bottom. Full has no gray strip under it.
    public static func originY(
        detent: JobSheetDetent,
        screenHeight: Double,
        topSafeArea: Double,
        isAccessibilitySize: Bool = false
    ) -> Double {
        screenHeight - height(
            detent: detent,
            screenHeight: screenHeight,
            topSafeArea: topSafeArea,
            isAccessibilitySize: isAccessibilitySize
        )
    }

    public static func bottomY(screenHeight: Double) -> Double {
        screenHeight
    }
}

/// One job: its Jobs row, its sheet, and its chat. The persisted root in jobs.json.
///
/// The app can read a job. It cannot change a copy and believe it was saved.
/// Every change goes through `JobsModel.append` or `JobsModel.edit`.
public struct JobSheetState: Equatable, Sendable, Identifiable, Codable {
    public let id: JobID
    public internal(set) var title: String
    /// When the first turn was written. `dateLabel(now:)` turns this into a row label.
    public let createdAt: Date
    /// The only copy of this job's chat. `conversation.id` is `ConversationID(id.rawValue)`.
    public internal(set) var conversation: Conversation
    /// Seeded when the first answer lands. Not regenerated after that.
    public internal(set) var steps: [JobSheetStep]
    public internal(set) var outcome: JobOutcome?
    /// Demo catalog `photo_id`. Not a `GaragePhoto.id`.
    public internal(set) var photoID: String?
    /// `GaragePhoto.id` of a real attached photo. Stored now; nothing sets it in #128.
    public internal(set) var garagePhotoID: String?
    /// Owner's words. Never auto-filled with specs.
    public internal(set) var notes: String
    public internal(set) var tags: [String]
    public internal(set) var whatFixed: String

    public init(
        id: JobID,
        title: String,
        createdAt: Date,
        conversation: Conversation,
        steps: [JobSheetStep] = [],
        outcome: JobOutcome? = nil,
        photoID: String? = nil,
        garagePhotoID: String? = nil,
        notes: String = "",
        tags: [String] = [],
        whatFixed: String = ""
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.conversation = conversation
        self.steps = steps
        self.outcome = outcome
        self.photoID = photoID
        self.garagePhotoID = garagePhotoID
        self.notes = notes
        self.tags = tags
        self.whatFixed = whatFixed
    }
}

extension JobSheetState {
    public var latestAssistant: AssistantMessage? {
        for message in conversation.messages.reversed() {
            if case let .assistant(assistant) = message {
                return assistant
            }
        }
        return nil
    }

    /// The sheet is shown once this job has an answer. A job that has only the
    /// owner's turn shows its chat and no sheet.
    public var showsSheet: Bool { latestAssistant != nil }

    public var answerText: String { latestAssistant?.answer.text ?? "" }

    public var citations: [Citation] {
        guard let latestAssistant, case let .found(found) = latestAssistant.answer else {
            return []
        }
        return found.citations
    }

    /// Latest found highlight. An attached photo does not invent an outline.
    public var highlight: HighlightRef? {
        guard let latestAssistant, case let .found(found) = latestAssistant.answer else {
            return nil
        }
        return found.highlight
    }

    public var hasPhoto: Bool { photoID != nil }
    public var headerTitle: String { JobSheetCopy.titlePrefix + title }

    /// "Today", "Yesterday", "Sep 28" (same year), or "Sep 28, 2025".
    /// en_US_POSIX month names so Linux and iOS agree.
    public func dateLabel(now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(createdAt, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(createdAt, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let createdYear = calendar.component(.year, from: createdAt)
        let nowYear = calendar.component(.year, from: now)
        formatter.dateFormat = createdYear == nowYear ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: createdAt)
    }

    /// `jobHistory.row.<slug>`. Lowercase, and each run of non-alphanumerics becomes one "-".
    public var rowIdentifier: String {
        "jobHistory.row.\(Self.slug(title))"
    }

    static func slug(_ title: String) -> String {
        var slug = ""
        var pendingSeparator = false
        let alphanumerics = CharacterSet.alphanumerics
        for character in title {
            let isAlphaNumeric = character.unicodeScalars.allSatisfy { alphanumerics.contains($0) }
            if isAlphaNumeric {
                if pendingSeparator, !slug.isEmpty {
                    slug.append("-")
                }
                pendingSeparator = false
                slug.append(contentsOf: character.lowercased())
            } else {
                pendingSeparator = true
            }
        }
        return slug
    }
}

/// Every change the sheet can make to a saved job.
public enum JobEdit: Equatable, Sendable {
    case outcome(JobOutcome)
    case notes(String)
    case whatFixed(String)
    case addTag(String)
    case removeTag(String)
    /// Sets `photoID` only. Tags, steps, and the answer stay as they are.
    case attachDemoPhoto(photoID: String)
    /// #129 calls this. No step-toggle UI in #128.
    case step(id: Int, isComplete: Bool)
}

extension JobSheetState {
    static func started(id: JobID, firstAsk: UserMessage, createdAt: Date) -> JobSheetState {
        JobSheetState(
            id: id,
            title: title(forFirstAsk: firstAsk.text),
            createdAt: createdAt,
            conversation: Conversation(
                id: ConversationID(rawValue: id.rawValue)!,
                messages: [.user(firstAsk)]
            )
        )
    }

    func appendingAsk(_ ask: UserMessage) -> JobSheetState {
        var next = self
        next.conversation = conversation.appending(.user(ask))
        return next
    }

    /// Appends the reply. On the first answer only, seeds empty steps, an empty photo, and empty tags.
    func receiving(_ reply: AssistantMessage, demoPhotoID: String?) -> JobSheetState {
        let firstAnswer = latestAssistant == nil
        var next = self
        next.conversation = conversation.appending(.assistant(reply))
        guard firstAnswer else { return next }
        if next.photoID == nil {
            next.photoID = demoPhotoID ?? Self.foundHighlight(in: reply)?.bayPhotoID.rawValue
        }
        if next.steps.isEmpty {
            let photo = next.photoID ?? DemoLaunchOptions.defaultPhotoID
            next.steps = JobSheetCopy.steps(
                photoID: photo,
                partID: Self.foundHighlight(in: reply)?.partID.rawValue
            )
        }
        if next.tags.isEmpty, let partID = Self.foundHighlight(in: reply)?.partID.rawValue {
            let hasOutline = Self.foundHighlight(in: reply)?.geometry != nil
            next.tags = DemoOutlineCatalog.tags(partID: partID, hasOutline: hasOutline)
        }
        return next
    }

    /// Nil when the edit changes nothing. The caller then skips the write.
    func applying(_ edit: JobEdit) -> JobSheetState? {
        var next = self
        switch edit {
        case let .outcome(outcome):
            guard self.outcome != outcome else { return nil }
            next.outcome = outcome
        case let .notes(notes):
            guard self.notes != notes else { return nil }
            next.notes = notes
        case let .whatFixed(whatFixed):
            guard self.whatFixed != whatFixed else { return nil }
            next.whatFixed = whatFixed
        case let .addTag(tag):
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !tags.contains(trimmed) else { return nil }
            next.tags.append(trimmed)
        case let .removeTag(tag):
            guard let index = tags.firstIndex(of: tag) else { return nil }
            next.tags.remove(at: index)
        case let .attachDemoPhoto(photoID):
            guard self.photoID != photoID else { return nil }
            next.photoID = photoID
        case let .step(id, isComplete):
            guard let index = steps.firstIndex(where: { $0.id == id }) else { return nil }
            guard steps[index].isComplete != isComplete else { return nil }
            next.steps[index].isComplete = isComplete
        }
        return next
    }

    /// First three words of the first ask. `JobSheetCopy.question` maps to "Cold idle".
    static func title(forFirstAsk text: String) -> String {
        if text == JobSheetCopy.question {
            return JobSheetCopy.title
        }
        let words = text.split(whereSeparator: \.isWhitespace).prefix(3)
        let title = words.joined(separator: " ")
        return title.isEmpty ? JobSheetCopy.title : title
    }

    private static func foundHighlight(in message: AssistantMessage) -> HighlightRef? {
        guard case let .found(found) = message.answer else { return nil }
        return found.highlight
    }
}

/// Scripted Cold idle job. Same demo data as #93 / #112.
public enum JobSheetScript {
    public static let userMessageID = MessageID(rawValue: "job-sheet-user")!
    public static let assistantMessageID = MessageID(rawValue: "job-sheet-assistant")!

    public static func selection(photoID: String, partID: String? = nil) -> DemoOutlineSelection {
        DemoOutlineCatalog.selection(photoID: photoID, partID: partID, state: .confident)
    }

    public static func highlight(photoID: String, partID: String? = nil) -> HighlightRef {
        let pick = selection(photoID: photoID, partID: partID)
        return HighlightRef(
            bayPhotoID: BayPhotoID(rawValue: pick.photoID) ?? BayPhotoID(rawValue: "fake-bay-photo-front")!,
            partID: PartID(rawValue: pick.partID) ?? PartID(rawValue: "fuse-relay-box")!,
            display: .outline,
            geometry: HighlightViewerScript.geometry(
                photoID: pick.photoID,
                partID: pick.partID,
                showingOutline: true
            ),
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

    public static let jobID = JobID(rawValue: "job-sheet-cold-idle")!

    /// Conversation holds the scripted ask and answer. Detent is not on the job.
    public static func job(photoID: String?, outcome: JobOutcome?, now: Date) -> JobSheetState {
        let resolvedPhoto = photoID ?? DemoLaunchOptions.defaultPhotoID
        let pick = selection(photoID: resolvedPhoto)
        let shown = highlight(photoID: resolvedPhoto)
        let found = FoundAnswer(
            text: JobSheetCopy.answer(photoID: resolvedPhoto),
            citations: [HighlightViewerScript.fixtureCitation],
            highlight: shown
        )
        let conversation = Conversation(
            id: ConversationID(rawValue: jobID.rawValue)!,
            messages: [
                .user(UserMessage(id: userMessageID, text: JobSheetCopy.question)!),
                .assistant(AssistantMessage(id: assistantMessageID, answer: .found(found!))),
            ]
        )
        return JobSheetState(
            id: jobID,
            title: JobSheetCopy.title,
            createdAt: now,
            conversation: conversation,
            steps: JobSheetCopy.steps(photoID: resolvedPhoto),
            outcome: outcome,
            photoID: photoID,
            tags: DemoOutlineCatalog.tags(partID: pick.partID, hasOutline: photoID != nil)
        )
    }
}

/// Sheet height only. The job lives on `JobsModel`.
@MainActor
@Observable
public final class JobSheetViewModel {
    public private(set) var detent: JobSheetDetent

    public var blocksChat: Bool { detent.blocksChat }

    public init(detent: JobSheetDetent = .collapsed) {
        self.detent = detent
    }

    public func open() {
        setDetent(.half)
    }

    public func close() {
        setDetent(.collapsed)
    }

    public func setDetent(_ detent: JobSheetDetent) {
        self.detent = detent
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
        } else         if translationHeight > 40 {
            collapseStep()
        }
    }
}
