import Foundation

/// Launch keys for the look-back screens. Matches the Figma frame names.
public enum LookBackScreen: String, CaseIterable, Hashable, Sendable {
    case jobHistory = "job-history"
    case scanLog = "scan-log"
}

/// Copy locked by tests. Matches the approved Jobs frame.
public enum JobHistoryCopy {
    public static let title = "Jobs"
    public static let subtitle = "Each one keeps its own chat."
    public static let back = "Back"
}

/// Copy locked by tests. Matches the approved Scan log frame.
public enum ScanLogCopy {
    public static let title = "Scan log"
    public static let subtitle = "Photos and outlines, filterable"
    public static let chips = [
        "all", "intake", "cooling", "ignition", "electrical", "fuel", "inspected", "watch",
    ]
    public static let selectedChip = "all"
    public static let empty = "Nothing matches."
    /// Fits a grid cell. The highlight card keeps `HighlightViewerCopy.referenceBanner`.
    public static let thumbBanner = "Not your truck"
}

/// Scripted Jobs list from the Figma frame. Memory only. Never written to jobs.json.
public enum JobHistoryScript {
    public static func jobs(now: Date, calendar: Calendar = .current) -> [JobSheetState] {
        [
            job(
                id: "job-history-cold-idle",
                title: "Cold idle",
                ask: JobSheetCopy.question,
                createdAt: now,
                outcome: .worked,
                photoID: "commons-hilux-2jz"
            ),
            job(
                id: "job-history-hard-start",
                title: "Hard start",
                ask: "Hard start",
                createdAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                outcome: .partly,
                photoID: "commons-supra-n5abh"
            ),
            job(
                id: "job-history-battery-light",
                title: "Battery light",
                ask: "Battery light",
                createdAt: latestPast(month: 9, day: 28, now: now, calendar: calendar),
                outcome: .didnt,
                photoID: "hrymx-2jz-ge-25308847029"
            ),
            job(
                id: "job-history-hose-check",
                title: "Hose check",
                ask: "Hose check",
                createdAt: latestPast(month: 9, day: 20, now: now, calendar: calendar),
                outcome: .worked,
                photoID: "flickr-robmarson-6763892857"
            ),
        ]
    }

    private static func job(
        id: String,
        title: String,
        ask: String,
        createdAt: Date,
        outcome: JobOutcome,
        photoID: String
    ) -> JobSheetState {
        let jobID = JobID(rawValue: id)!
        let highlight = JobSheetScript.highlight(photoID: photoID)
        let found = FoundAnswer(
            text: JobSheetCopy.answer(photoID: photoID),
            citations: [HighlightViewerScript.fixtureCitation],
            highlight: highlight
        )!
        let pick = JobSheetScript.selection(photoID: photoID)
        return JobSheetState(
            id: jobID,
            title: title,
            createdAt: createdAt,
            conversation: Conversation(
                id: ConversationID(rawValue: id)!,
                messages: [
                    .user(UserMessage(id: MessageID(rawValue: "\(id)-user")!, text: ask)!),
                    .assistant(
                        AssistantMessage(
                            id: MessageID(rawValue: "\(id)-assistant")!,
                            answer: .found(found)
                        )
                    ),
                ]
            ),
            steps: JobSheetCopy.steps(photoID: photoID),
            outcome: outcome,
            photoID: photoID,
            tags: DemoOutlineCatalog.tags(partID: pick.partID, hasOutline: true)
        )
    }

    /// Most recent month/day strictly before `now`'s day. Noon, so a DST shift cannot change the day.
    private static func latestPast(month: Int, day: Int, now: Date, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: now)
        let thisYear = calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        )
        let lastYear = calendar.date(
            from: DateComponents(year: year - 1, month: month, day: day, hour: 12)
        )
        if let thisYear, calendar.startOfDay(for: thisYear) < calendar.startOfDay(for: now) {
            return thisYear
        }
        return lastYear ?? now
    }
}

/// One scan-log cell. Outline via #112 `resolve()`, never a box.
public struct ScanLogEntry: Equatable, Sendable, Identifiable {
    public var id: String
    public var photoID: String
    public var source: HighlightViewerState
    /// Part caption under the photo. An outline uses the catalog short tag. A miss is an em dash.
    public var tagLabel: String
    /// Filter chip this cell belongs to. Separate from `tagLabel`, so a filter does not rename the part.
    public var filterTag: String

    public init(
        id: String,
        photoID: String,
        source: HighlightViewerState,
        tagLabel: String,
        filterTag: String
    ) {
        self.id = id
        self.photoID = photoID
        self.source = source
        self.tagLabel = tagLabel
        self.filterTag = filterTag
    }

    public func presentation(flags: FeatureFlags = .v1) -> HighlightViewerPresentation {
        HighlightViewerPresentation.resolve(source: source, flags: flags, photoID: photoID)
    }

    public func geometry(flags: FeatureFlags = .v1) -> HighlightGeometry? {
        let shown = presentation(flags: flags)
        return HighlightViewerScript.geometry(
            photoID: shown.outlinePhotoID,
            partID: shown.partID,
            showingOutline: shown.showsOutline
        )
    }

    /// Short cell label. Nil when the highlight card would not show a banner.
    public func cellBanner(flags: FeatureFlags = .v1) -> String? {
        presentation(flags: flags).banner == nil ? nil : ScanLogCopy.thumbBanner
    }
}

/// Scripted 3×3 grid from the Figma frame. One reference cell keeps the banner.
public enum ScanLogScript {
    public static let photos = [
        "commons-hilux-2jz",
        "commons-supra-n5abh",
        "hrymx-2jz-ge-25308847029",
        "flickr-robmarson-6763892857",
    ]

    /// Outline / none pattern matches the Figma 3×3.
    public static let cellStates: [HighlightViewerState] = [
        .confident, .confident, .notFound,
        .confident, .notFound, .confident,
        .reference, .confident, .notFound,
    ]

    /// One topic per cell. Independent of the part caption.
    public static let filterTags = [
        "intake",
        "cooling",
        "ignition",
        "electrical",
        "fuel",
        "inspected",
        "watch",
        "intake",
        "electrical",
    ]

    public static var entries: [ScanLogEntry] {
        cellStates.enumerated().map { index, source in
            let photoID = photos[index % photos.count]
            let shown = HighlightViewerPresentation.resolve(source: source, photoID: photoID)
            return ScanLogEntry(
                id: "scan-log-\(index)",
                photoID: photoID,
                source: source,
                tagLabel: shown.showsOutline
                    ? DemoOutlineCatalog.shortTag(partID: shown.partID)
                    : "—",
                filterTag: filterTags[index]
            )
        }
    }
}

public enum ScanLogFilter {
    public static func shown(_ entries: [ScanLogEntry], chip: String) -> [ScanLogEntry] {
        if chip == "all" {
            return entries
        }
        return entries.filter { $0.filterTag == chip }
    }
}
