import SidekickCore
import SwiftUI

/// Three first-open screens. No animation. Skip or Start chatting lands on chat.
struct OnboardingFlow: View {
    @Binding var page: OnboardingPage
    var onFinished: () -> Void

    var body: some View {
        NavigationStack {
            pageBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip", action: onFinished)
                            .accessibilityIdentifier("onboarding.skip")
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    footer
                }
        }
        .accessibilityIdentifier("onboarding.\(page.rawValue)")
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
            .foregroundStyle(Color(.systemBackground))
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier(page == .garage ? "onboarding.start" : "onboarding.next")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color(.systemGroupedBackground))
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
            VStack(alignment: .leading, spacing: 20) {
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
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
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
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("onboarding.howItWorks")
    }
}

/// Display-only garage rows. Used on first-open screen 3 and from Chat → Garage.
struct GarageListView: View {
    var showsHeader = false

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
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
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
            fact.isConfirmed
                ? Color(.secondarySystemGroupedBackground)
                : Color.secondary.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            if fact.isConfirmed {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("garage.row.\(fact.id)")
        .accessibilityLabel("\(fact.label), \(fact.value)")
    }
}

/// Abstract NA 2JZ bay. Not the truck. Magenta outline on the air box.
private struct BayPlaceholderView: View {
    private static let fuchsia = Color(red: 1, green: 0, blue: 1)

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.22))

                VStack(spacing: h * 0.06) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                        .overlay {
                            Text("radiator area")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: w * 0.84, height: h * 0.14)

                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.28))
                            .frame(width: w * 0.64, height: h * 0.46)

                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(.systemBackground).opacity(0.7))
                            .overlay {
                                Text("air box")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Self.fuchsia, lineWidth: 2.4)
                                    .padding(-3)
                            }
                            .frame(width: w * 0.44, height: h * 0.18)
                            .offset(y: -h * 0.08)
                    }

                    HStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: w * 0.18, height: h * 0.14)
                        Spacer()
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: w * 0.16, height: h * 0.16)
                    }
                    .padding(.horizontal, w * 0.08)
                }
                .padding(.top, h * 0.08)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
