import SidekickCore
import SwiftUI

/// White 24pt sheet used when a citation chip is tapped. The garage dim is the scrim.
struct PresentedCitation: Identifiable, Hashable {
    var citation: Citation

    var id: String {
        "\(citation.docID.rawValue)#\(citation.page.rawValue)"
    }
}

extension View {
    /// `onAsk` closes the sheet, then pins the page the owner was reading to the chat composer.
    func citationSheet(_ citation: Binding<Citation?>, onAsk: ((PageRef) -> Void)? = nil) -> some View {
        modifier(CitationSheetModifier(citation: citation, onAsk: onAsk))
    }
}

private struct CitationSheetModifier: ViewModifier {
    @Binding var citation: Citation?
    var onAsk: ((PageRef) -> Void)?
    @State private var coverage = 0.0
    @State private var scrimVisible = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if scrimVisible {
                    GarageDim(coverage: coverage, identifier: "citation.dim", label: "Close manual page") {
                        citation = nil
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: scrimVisible)
            .onAppear {
                if citation != nil { scrimVisible = true }
            }
            .onChange(of: citation != nil) { _, isPresented in
                if isPresented { scrimVisible = true }
            }
            .sheet(item: presented, onDismiss: { scrimVisible = false }) { presented in
                CitationPageView(citation: presented.citation, onAsk: askHandler)
                    .background {
                        GarageSheetPositionReader(coverage: $coverage)
                    }
                    .modifier(
                        AccessibilityLaunchModifier(
                            enabled: DemoLaunchOptions.parse().prefersAccessibilitySize
                        )
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color.white)
                    .presentationCornerRadius(CGFloat(JobSheetLayout.topCornerRadius))
                    .preferredColorScheme(.light)
            }
    }

    private var presented: Binding<PresentedCitation?> {
        Binding(
            get: { citation.map(PresentedCitation.init) },
            set: { citation = $0?.citation }
        )
    }

    private var askHandler: ((PageRef) -> Void)? {
        guard let onAsk else { return nil }
        return { page in
            citation = nil
            onAsk(page)
        }
    }
}
