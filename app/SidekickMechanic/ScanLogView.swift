import SidekickCore
import SwiftUI
import UIKit

/// Scan log grid from the approved Figma frame. Outlines use #112's public renderer.
struct ScanLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: DemoImageStore
    var configuration: ChatClientConfiguration
    var flags: FeatureFlags = .v1
    var onOpenCell: (ScanLogEntry) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8, alignment: .top),
        GridItem(.flexible(), spacing: 8, alignment: .top),
        GridItem(.flexible(), spacing: 8, alignment: .top),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(ScanLogCopy.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scanLog.subtitle")
                chipRow
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(ScanLogScript.entries) { entry in
                        Button {
                            onOpenCell(entry)
                        } label: {
                            cell(entry)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .clipped()
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("scanLog.cell.\(entry.id)")
                        .accessibilityHint("Opens the highlight card")
                    }
                }
            }
            .padding(16)
        }
        .background(JobSheetChrome.screen)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            LookBackPaperHeader(
                title: ScanLogCopy.title,
                showScanLog: false,
                onBack: { dismiss() }
            )
        }
        .task {
            if store.catalog == nil {
                await store.load(from: configuration)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scanLog.grid")
    }

    private var chipRow: some View {
        WrappingHStack(spacing: 6, lineSpacing: 6) {
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
                    .fixedSize()
                    .accessibilityIdentifier("scanLog.chip.\(chip)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("scanLog.chips")
    }

    private func cell(_ entry: ScanLogEntry) -> some View {
        let presentation = entry.presentation(flags: flags)
        let thumbPhotoID = presentation.showsOutline ? presentation.outlinePhotoID : entry.photoID
        let confirm = presentation.outlineStroke == .dashed
        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .top) {
                JobSheetChrome.emptyPhoto
                DemoHighlightView(
                    image: store.images[thumbPhotoID] ?? HighlightPlaceholderImage.make(),
                    geometry: entry.geometry(flags: flags),
                    style: .outline,
                    confirm: confirm,
                    dashed: confirm,
                    attribution: "",
                    shareAlike: false,
                    notFound: !presentation.showsOutline,
                    cornerRadius: 0,
                    outlineInk: .lookBackTile(dashed: confirm),
                    fillsContainer: true
                )
                if let banner = entry.cellBanner(flags: flags) {
                    Text(banner)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(JobSheetChrome.paper.opacity(0.94))
                        .padding(4)
                        .accessibilityIdentifier("scanLog.referenceBanner")
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipped()
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(entry.tagLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Intrinsic-width chips that wrap, instead of equal-width grid columns.
private struct WrappingHStack: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        let height = y + rowHeight
        let width = maxWidth.isFinite ? maxWidth : usedWidth
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
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
