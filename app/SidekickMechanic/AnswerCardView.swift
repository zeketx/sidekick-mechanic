import SidekickCore
import SwiftUI

/// Layout for one assistant reply. Copy and visibility come from `AnswerCardContent`.
struct AnswerCardView: View {
    let content: AnswerCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let statusTitle = content.statusTitle {
                Label(statusTitle, systemImage: "book.closed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("answerCard.status")
            }

            Text(content.text)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("answerCard.text")

            if !content.chips.isEmpty {
                chipRow
            }

            if content.showsHighlightSlot, let highlightLabel = content.highlightAccessibilityLabel {
                highlightSlot(highlightLabel)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(content.accessibilityIdentifier)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(content.chips) { chip in
                    NavigationLink {
                        CitationPageView(citation: chip.citation)
                    } label: {
                        Text(chip.label)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.background, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(Color.secondary.opacity(0.35))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chip.label)
                    .accessibilityHint("Opens the manual page")
                    .accessibilityIdentifier("answerCard.chip.\(chip.id)")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("answerCard.chips")
    }

    private func highlightSlot(_ accessibilityLabel: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.title2)
                .accessibilityHidden(true)
            Text("Bay photo")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("answerCard.highlight")
    }

    private var cardFill: Color {
        switch content.presentation {
        case .found:
            Color.secondary.opacity(0.15)
        case .notFoundInManual:
            Color.secondary.opacity(0.22)
        }
    }
}

private struct AnswerCardPreview: View {
    let answer: Answer

    var body: some View {
        NavigationStack {
            ScrollView {
                AnswerCardView(content: AnswerCardContent(answer: answer))
                    .padding(16)
            }
            .background(.background)
        }
    }
}

#Preview("Light") {
    AnswerCardPreview(answer: AnswerCardFixture.withHighlight)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AnswerCardPreview(answer: AnswerCardFixture.withHighlight)
        .preferredColorScheme(.dark)
}

#Preview("Large Dynamic Type") {
    AnswerCardPreview(answer: AnswerCardFixture.withHighlight)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Found") {
    AnswerCardPreview(answer: AnswerCardFixture.withCitations)
}

#Preview("Refusal") {
    AnswerCardPreview(answer: AnswerCardFixture.refusal)
}

#Preview("No highlight") {
    AnswerCardPreview(answer: AnswerCardFixture.plain)
}
