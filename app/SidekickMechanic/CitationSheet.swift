import SidekickCore
import SwiftUI

/// White 24pt sheet used when a citation chip is tapped. System dimming is the scrim.
struct PresentedCitation: Identifiable, Hashable {
    var citation: Citation

    var id: String {
        "\(citation.docID.rawValue)#\(citation.page.rawValue)"
    }
}

extension View {
    func citationSheet(_ citation: Binding<Citation?>) -> some View {
        sheet(
            item: Binding(
                get: { citation.wrappedValue.map(PresentedCitation.init) },
                set: { citation.wrappedValue = $0?.citation }
            )
        ) { presented in
            CitationPageView(citation: presented.citation)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(JobSheetChrome.paper)
                .presentationCornerRadius(CGFloat(JobSheetLayout.topCornerRadius))
        }
    }
}
