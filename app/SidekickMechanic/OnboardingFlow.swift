import SidekickCore
import SwiftUI
import UIKit

/// Three first-open screens. No animation. Skip or Start chatting lands on chat.
struct OnboardingFlow: View {
    @Binding var page: OnboardingPage
    var onFinished: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            pageBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(OnboardingPalette.paper)
        .accessibilityIdentifier("onboarding.\(page.rawValue)")
    }

    private var header: some View {
        ZStack {
            Text(navigationTitle)
                .font(.headline)
            HStack {
                Spacer()
                Button("Skip", action: onFinished)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.skip")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var pageBody: some View {
        switch page {
        case .welcome:
            WelcomeOnboardingPage()
        case .howItWorks:
            HowItWorksOnboardingPage()
        case .garage:
            GarageListView(showsHeader: true)
        }
    }

    private var navigationTitle: String {
        switch page {
        case .welcome: "Sidekick"
        case .howItWorks: "How it works"
        case .garage: "Your garage"
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            pageDots
            Button(action: advanceOrFinish) {
                Text(page == .garage ? "Start chatting" : "Next")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(OnboardingPalette.paper)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier(page == .garage ? "onboarding.start" : "onboarding.next")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(OnboardingPalette.paper)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingPage.allCases, id: \.self) { candidate in
                Circle()
                    .fill(candidate == page ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Screen \(pageIndex) of 3")
        .accessibilityIdentifier("onboarding.pageDots")
    }

    private var pageIndex: Int {
        (OnboardingPage.allCases.firstIndex(of: page) ?? 0) + 1
    }

    private func advanceOrFinish() {
        if let next = page.next {
            page = next
        } else {
            onFinished()
        }
    }
}

/// Welcome: one-line pitch, truck identity, abstract bay with a magenta outline.
private struct WelcomeOnboardingPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BayPlaceholderView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .accessibilityLabel("Placeholder engine bay. Air box outlined.")

                Text(OnboardingCopy.welcomeTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Text(OnboardingCopy.welcomeBody)
                    .font(.body)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(OnboardingCopy.truckName)
                        .font(.subheadline.weight(.semibold))
                    Text(OnboardingCopy.truckMeta)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OnboardingPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.22))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("onboarding.welcome")
    }
}

/// How it works: chat → cited answer → outline.
private struct HowItWorksOnboardingPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(OnboardingCopy.howItWorksTitle)
                    .font(.title2.weight(.bold))

                ForEach(OnboardingCopy.steps, id: \.title) { step in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.title)
                            .font(.headline)
                        Text(step.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OnboardingPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.22))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("onboarding.howItWorks")
    }
}

/// Display-only garage rows. Used on first-open screen 3 and from Chat → Garage.
struct GarageListView: View {
    var showsHeader = false
    var canvas: Color = OnboardingPalette.paper

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if showsHeader {
                    Text(OnboardingCopy.garageTitle)
                        .font(.title2.weight(.bold))
                    Text(GarageFacts.tbdNotice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(GarageFacts.tbdNotice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                sectionLabel("Confirmed")
                ForEach(GarageFacts.confirmed) { fact in
                    GarageRowView(fact: fact)
                }

                sectionLabel("Still TBD")
                    .padding(.top, 8)
                ForEach(GarageFacts.pending) { fact in
                    GarageRowView(fact: fact)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(canvas)
        .accessibilityIdentifier("onboarding.garage")
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct GarageRowView: View {
    let fact: GarageFact

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(fact.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(fact.value)
                .font(.subheadline.weight(fact.isConfirmed ? .semibold : .bold))
                .foregroundStyle(fact.isConfirmed ? .primary : .secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            fact.isConfirmed ? OnboardingPalette.card : OnboardingPalette.pendingRow,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            if fact.isConfirmed {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.22))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("garage.row.\(fact.id)")
        .accessibilityLabel("\(fact.label), \(fact.value)")
    }
}

/// Neutral paper, not `systemGroupedBackground` (blue-gray on iOS).
private enum OnboardingPalette {
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.11, alpha: 1)
            : UIColor(red: 0.957, green: 0.957, blue: 0.957, alpha: 1)
    })
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.16, alpha: 1)
            : UIColor.white
    })
    static let pendingRow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.20, alpha: 1)
            : UIColor(white: 0.91, alpha: 1)
    })
    static let fuchsia = Color(red: 1, green: 0, blue: 1)
    static let fuchsiaFill = Color(red: 1, green: 0.82, blue: 1).opacity(0.55)
}

/// Abstract NA 2JZ bay. Not the truck. Organic magenta outline on the air box.
private struct BayPlaceholderView: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))

                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.28), lineWidth: 1)
                        .background {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(OnboardingPalette.card.opacity(0.7))
                        }
                        .overlay {
                            Text("radiator area")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: w * 0.84, height: h * 0.12)
                        .padding(.top, h * 0.07)

                    Spacer(minLength: 0)

                    ZStack {
                        OrganicPartOutline()
                            .fill(OnboardingPalette.fuchsiaFill)
                        OrganicPartOutline()
                            .stroke(OnboardingPalette.fuchsia, lineWidth: 2.2)
                        Text("air box")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: w * 0.50, height: h * 0.22)

                    Spacer(minLength: 0)

                    HStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(OnboardingPalette.card.opacity(0.85))
                            .frame(width: w * 0.16, height: h * 0.12)
                        Spacer()
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(OnboardingPalette.card.opacity(0.85))
                            .frame(width: w * 0.16, height: h * 0.12)
                    }
                    .padding(.horizontal, w * 0.08)

                    Text(OnboardingCopy.bayCaption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .padding(.bottom, h * 0.05)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Loose closed curve through irregular points. A bounding box is never the highlight.
private struct OrganicPartOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let units: [CGPoint] = [
            CGPoint(x: 0.07, y: 0.40),
            CGPoint(x: 0.16, y: 0.14),
            CGPoint(x: 0.34, y: 0.04),
            CGPoint(x: 0.55, y: 0.11),
            CGPoint(x: 0.76, y: 0.03),
            CGPoint(x: 0.93, y: 0.20),
            CGPoint(x: 0.98, y: 0.46),
            CGPoint(x: 0.90, y: 0.76),
            CGPoint(x: 0.70, y: 0.96),
            CGPoint(x: 0.44, y: 0.91),
            CGPoint(x: 0.20, y: 0.84),
            CGPoint(x: 0.03, y: 0.60),
        ]
        let points = units.map {
            CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height)
        }
        return Self.closedCatmullRom(points)
    }

    private static func closedCatmullRom(_ points: [CGPoint]) -> Path {
        guard points.count >= 3 else { return Path() }
        let count = points.count
        func at(_ index: Int) -> CGPoint {
            points[(index % count + count) % count]
        }
        var path = Path()
        path.move(to: points[0])
        for index in 0..<count {
            let p0 = at(index - 1)
            let p1 = at(index)
            let p2 = at(index + 1)
            let p3 = at(index + 2)
            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Onboarding 1") {
    OnboardingFlow(page: .constant(.welcome), onFinished: {})
        .preferredColorScheme(.light)
}

#Preview("Onboarding 2") {
    OnboardingFlow(page: .constant(.howItWorks), onFinished: {})
        .preferredColorScheme(.light)
}

#Preview("Onboarding 3") {
    OnboardingFlow(page: .constant(.garage), onFinished: {})
        .preferredColorScheme(.light)
}

#Preview("Onboarding 1 Dark") {
    OnboardingFlow(page: .constant(.welcome), onFinished: {})
        .preferredColorScheme(.dark)
}

#Preview("Onboarding XL") {
    OnboardingFlow(page: .constant(.welcome), onFinished: {})
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Garage sheet") {
    NavigationStack {
        GarageListView()
            .navigationTitle("Your garage")
            .navigationBarTitleDisplayMode(.inline)
    }
}
