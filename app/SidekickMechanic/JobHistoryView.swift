import SidekickCore
import SwiftUI
import UIKit

/// Jobs list from the approved Figma frame. Peeks use #112's public outline renderer.
struct JobHistoryView: View {
    @Bindable var store: DemoImageStore
    var configuration: ChatClientConfiguration
    var flags: FeatureFlags = .v1
    var onOpenJob: (JobHistoryRow) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(JobHistoryCopy.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("jobHistory.subtitle")
                ForEach(JobHistoryScript.rows) { row in
                    Button {
                        onOpenJob(row)
                    } label: {
                        rowCard(row)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("jobHistory.row.\(row.job.title.lowercased().replacingOccurrences(of: " ", with: "-"))")
                    .accessibilityHint("Opens this job sheet")
                }
            }
            .padding(16)
        }
        .background(JobSheetChrome.screen)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(JobHistoryCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Scan log", value: LookBackScreen.scanLog)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("jobHistory.scanLog")
            }
        }
        .task {
            if store.catalog == nil {
                await store.load(from: configuration)
            }
        }
        .accessibilityIdentifier("jobHistory.list")
    }

    private func rowCard(_ row: JobHistoryRow) -> some View {
        let presentation = HighlightViewerPresentation.resolve(
            source: HighlightViewerState.fromDemo(
                display: row.job.highlight?.display,
                highlight: row.job.highlight
            ),
            flags: flags,
            photoID: row.job.photoID ?? DemoLaunchOptions.defaultPhotoID,
            partID: row.job.highlight?.partID.rawValue
        )
        let geometry = presentation.showsOutline
            ? (row.job.highlight?.geometry ?? HighlightViewerScript.geometry(
                photoID: presentation.outlinePhotoID,
                partID: presentation.partID,
                showingOutline: true
            ))
            : nil
        return HStack(alignment: .center, spacing: 12) {
            DemoHighlightView(
                image: store.images[row.job.photoID ?? ""] ?? HighlightPlaceholderImage.make(),
                geometry: geometry,
                style: .outline,
                confirm: presentation.outlineStroke == .dashed,
                dashed: presentation.outlineStroke == .dashed,
                attribution: "Demo data. Not Zeke's truck.",
                shareAlike: false,
                notFound: !presentation.showsOutline,
                cornerRadius: 8
            )
            .frame(width: 44, height: 44)
            .clipped()
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.job.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(row.dateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            outcomeBadge(row.job.outcome)
        }
        .padding(12)
        .background(JobSheetChrome.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22))
        }
    }

    @ViewBuilder
    private func outcomeBadge(_ outcome: JobOutcome?) -> some View {
        if let outcome {
            let filled = outcome == .worked
            Text(outcome.label)
                .font(.caption.weight(filled ? .semibold : .regular))
                .foregroundStyle(filled ? JobSheetChrome.paper : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(filled ? Color.primary : Color.clear, in: Capsule())
                .overlay {
                    if !filled {
                        Capsule().strokeBorder(Color.secondary.opacity(0.4))
                    }
                }
                .accessibilityIdentifier("jobHistory.badge.\(outcome.rawValue)")
        }
    }
}

#Preview("Jobs") {
    NavigationStack {
        JobHistoryView(
            store: DemoImageStore(),
            configuration: ChatClientConfiguration(baseURL: URL(string: "http://localhost:8000")!),
            onOpenJob: { _ in }
        )
    }
}

#Preview("Jobs Dark") {
    NavigationStack {
        JobHistoryView(
            store: DemoImageStore(),
            configuration: ChatClientConfiguration(baseURL: URL(string: "http://localhost:8000")!),
            onOpenJob: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Jobs Large Dynamic Type") {
    NavigationStack {
        JobHistoryView(
            store: DemoImageStore(),
            configuration: ChatClientConfiguration(baseURL: URL(string: "http://localhost:8000")!),
            onOpenJob: { _ in }
        )
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
