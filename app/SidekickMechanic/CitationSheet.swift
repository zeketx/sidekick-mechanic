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
                .modifier(
                    AccessibilityLaunchModifier(
                        enabled: DemoLaunchOptions.parse().prefersAccessibilitySize
                    )
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(JobSheetChrome.paper)
                .presentationCornerRadius(CGFloat(JobSheetLayout.topCornerRadius))
        }
    }
}

extension View {
    /// A 1pt leaf at the top of a sheet so a UI test can measure header clearance.
    func sheetTopMarker(_ identifier: String) -> some View {
        Text(" ")
            .font(.system(size: 1))
            .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel("Sheet top")
    }

    /// Space from the top edge of a grabber sheet down to the header controls.
    /// The job sheet draws its own capsule, so it only adds the remainder.
    func sheetHeaderClearance(underCustomGrabber: Bool = false) -> some View {
        padding(
            .top,
            CGFloat(
                underCustomGrabber
                    ? JobSheetLayout.headerPaddingUnderGrabber
                    : JobSheetLayout.headerTopClearance
            )
        )
    }
}
