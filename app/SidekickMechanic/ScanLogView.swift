import SidekickCore
import SwiftUI
import UIKit

/// Scan log grid from the approved Figma frame. Outlines use #112's public renderer.
struct ScanLogView: View {
    @Bindable var store: DemoImageStore
    var configuration: ChatClientConfiguration
    var flags: FeatureFlags = .v1
    var onOpenCell: (ScanLogEntry) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(ScanLogCopy.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scanLog.subtitle")
                chipRow
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(ScanLogScript.entries) { entry in
                        Button {
                            onOpenCell(entry)
                        } label: {
                            cell(entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("scanLog.cell.\(entry.id)")
                        .accessibilityHint("Opens the highlight card")
                    }
                }
            }
            .padding(16)
        }
        .background(JobSheetChrome.screen)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(ScanLogCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.catalog == nil {
                await store.load(from: configuration)
            }
        }
        .accessibilityIdentifier("scanLog.grid")
    }

    private var chipRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 72), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(ScanLogCopy.chips, id: \.self) { chip in
                let selected = chip == ScanLogCopy.selectedChip
                Text(chip)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? JobSheetChrome.paper : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selected ? Color.primary : JobSheetChrome.paper, in: Capsule())
                    .overlay {
                        if !selected {
                            Capsule().strokeBorder(Color.secondary.opacity(0.35))
                        }
                    }
                    .accessibilityIdentifier("scanLog.chip.\(chip)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityIdentifier("scanLog.chips")
    }

    private func cell(_ entry: ScanLogEntry) -> some View {
        let presentation = entry.presentation(flags: flags)
        let thumbPhotoID = presentation.showsOutline ? presentation.outlinePhotoID : entry.photoID
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .top) {
                DemoHighlightView(
                    image: store.images[thumbPhotoID] ?? HighlightPlaceholderImage.make(),
                    geometry: entry.geometry(flags: flags),
                    style: .outline,
                    confirm: presentation.outlineStroke == .dashed,
                    dashed: presentation.outlineStroke == .dashed,
                    attribution: "Demo data. Not Zeke's truck.",
                    shareAlike: false,
                    notFound: !presentation.showsOutline,
                    cornerRadius: 10
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                if let banner = presentation.banner {
                    Text(banner)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(JobSheetChrome.paper.opacity(0.94))
                        .padding(6)
                        .accessibilityIdentifier("scanLog.referenceBanner")
                }
            }
            Text(entry.tagLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Scan log") {
    NavigationStack {
        ScanLogView(
            store: DemoImageStore(),
            configuration: ChatClientConfiguration(baseURL: URL(string: "http://localhost:8000")!),
            onOpenCell: { _ in }
        )
    }
}

#Preview("Scan log Dark") {
    NavigationStack {
        ScanLogView(
            store: DemoImageStore(),
            configuration: ChatClientConfiguration(baseURL: URL(string: "http://localhost:8000")!),
            onOpenCell: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Scan log Large Dynamic Type") {
    NavigationStack {
        ScanLogView(
            store: DemoImageStore(),
            configuration: ChatClientConfiguration(baseURL: URL(string: "http://localhost:8000")!),
            onOpenCell: { _ in }
        )
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
