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
        switch self {
        case .closeout, .full: .worked
        case .collapsed, .half: nil
        }
    }
}

/// One scripted checkbox on the half sheet. Not the later #97 editor.
public struct JobSheetStep: Equatable, Sendable, Identifiable {
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
    /// Owner's words. Not a manual citation. Never auto-filled with specs.
    public var notes: String
    /// Same chip set as the highlight card (HL-6), plus user-defined tags.
    public var tags: [String]
    /// Optional close-out line under "How did it go?".
    public var whatFixed: String

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
        outcome: JobOutcome? = nil,
        notes: String = "",
        tags: [String] = [],
        whatFixed: String = ""
    ) {
        self.sourceMessageID = sourceMessageID
        self.title = title
        self.answerText = answerText
        self.citations = citations
        self.photoID = photoID
        self.highlight = highlight
        self.detent = detent
        self.outcome = outcome
        self.notes = notes
        self.tags = tags
        self.whatFixed = whatFixed
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

    public static func makeJob(
        detent: JobSheetDetent,
        photoID: String?,
        outcome: JobOutcome? = nil
    ) -> JobSheetState {
        let resolvedPhoto = photoID ?? DemoLaunchOptions.defaultPhotoID
        let pick = selection(photoID: resolvedPhoto)
        return JobSheetState(
            sourceMessageID: assistantMessageID,
            title: JobSheetCopy.title,
            answerText: JobSheetCopy.answer(photoID: resolvedPhoto),
            citations: [HighlightViewerScript.fixtureCitation],
            photoID: photoID,
            highlight: photoID.map { highlight(photoID: $0) },
            detent: detent,
            outcome: outcome,
            tags: DemoOutlineCatalog.tags(partID: pick.partID, hasOutline: photoID != nil)
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
        let highlight = Self.highlight(from: assistant.answer)
            ?? photoID.map { JobSheetScript.highlight(photoID: $0) }
        let partID = highlight?.partID.rawValue
        job = JobSheetState(
            sourceMessageID: assistant.id,
            title: Self.title(from: messages),
            answerText: assistant.answer.text,
            citations: Self.citations(from: assistant.answer),
            photoID: photoID ?? highlight?.bayPhotoID.rawValue,
            highlight: highlight,
            detent: .collapsed,
            outcome: nil,
            tags: partID.map { DemoOutlineCatalog.tags(partID: $0, hasOutline: highlight?.geometry != nil) } ?? []
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

    public func setNotes(_ notes: String) {
        update { $0.notes = notes }
    }

    public func setWhatFixed(_ whatFixed: String) {
        update { $0.whatFixed = whatFixed }
    }

    public func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update { job in
            if !job.tags.contains(trimmed) {
                job.tags.append(trimmed)
            }
        }
    }

    public func removeTag(_ tag: String) {
        update { $0.tags.removeAll { $0 == tag } }
    }

    /// Binds a photo to this job only. Does not write a bay-map frame.
    public func attachPhoto(photoID: String) {
        update { job in
            job.photoID = photoID
            job.highlight = JobSheetScript.highlight(photoID: photoID)
            job.answerText = JobSheetCopy.answer(photoID: photoID)
            let pick = JobSheetScript.selection(photoID: photoID)
            job.tags = DemoOutlineCatalog.tags(partID: pick.partID, hasOutline: true)
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
