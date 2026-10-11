/// Launch keys for the look-back screens. Matches the Figma frame names.
public enum LookBackScreen: String, CaseIterable, Hashable, Sendable {
    case jobHistory = "job-history"
    case scanLog = "scan-log"
}

/// Copy locked by tests. Matches the approved Jobs frame.
public enum JobHistoryCopy {
    public static let title = "Jobs"
    public static let subtitle = "One row per ask"
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

/// One Jobs row. Wraps #113's `JobSheetState`. Session-only scripted data.
public struct JobHistoryRow: Equatable, Sendable, Identifiable {
    public var id: MessageID { job.id }
    public var job: JobSheetState
    public var dateLabel: String

    public init(job: JobSheetState, dateLabel: String) {
        self.job = job
        self.dateLabel = dateLabel
    }

    /// Tap opens that job sheet at half height. Does not append chat (JH-2 later).
    public func openedSheet() -> JobSheetState {
        var job = job
        job.detent = .half
        return job
    }
}

/// Scripted Jobs list from the Figma frame.
public enum JobHistoryScript {
    public static var rows: [JobHistoryRow] {
        [
            row(
                id: "job-history-cold-idle",
                title: "Cold idle",
                date: "Today",
                outcome: .worked,
                photoID: "commons-hilux-2jz"
            ),
            row(
                id: "job-history-hard-start",
                title: "Hard start",
                date: "Yesterday",
                outcome: .partly,
                photoID: "commons-supra-n5abh"
            ),
            row(
                id: "job-history-battery-light",
                title: "Battery light",
                date: "Sep 28",
                outcome: .didnt,
                photoID: "hrymx-2jz-ge-25308847029"
            ),
            row(
                id: "job-history-hose-check",
                title: "Hose check",
                date: "Sep 20",
                outcome: .worked,
                photoID: "flickr-robmarson-6763892857"
            ),
        ]
    }

    public static func row(
        id: String,
        title: String,
        date: String,
        outcome: JobOutcome,
        photoID: String
    ) -> JobHistoryRow {
        JobHistoryRow(
            job: JobSheetState(
                sourceMessageID: MessageID(rawValue: id)!,
                title: title,
                answerText: JobSheetCopy.answer(photoID: photoID),
                citations: [HighlightViewerScript.fixtureCitation],
                photoID: photoID,
                highlight: JobSheetScript.highlight(photoID: photoID),
                detent: .collapsed,
                outcome: outcome
            ),
            dateLabel: date
        )
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
