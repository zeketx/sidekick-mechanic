import SidekickCore
import SwiftUI
import UIKit

private struct TopChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Message list and composer. Assistant replies use `AnswerCardView`.
struct ChatScreen: View {
    @Bindable var jobs: JobsModel
    @Bindable var model: ChatViewModel
    var backendURL: URL
    var launch: DemoLaunchOptions
    var onOpenGarage: (() -> Void)?
    @State private var demoImages: DemoImageStore
    @State private var presentedViewer: HighlightViewerSession?
    @State private var presentedCitation: Citation?
    @State private var jobSheet: JobSheetViewModel
    @State private var lookBackPath: [LookBackVisit]
    @State private var lookBackGeneration: Int
    @State private var topChromeHeight: CGFloat
    @State private var windowHeight: CGFloat
    @State private var topSafeArea: CGFloat
    @State private var bottomSafeArea: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        jobs: JobsModel,
        model: ChatViewModel,
        backendURL: URL = AppConfig.backendURL,
        launch: DemoLaunchOptions = DemoLaunchOptions.parse(),
        onOpenGarage: (() -> Void)? = nil
    ) {
        self.jobs = jobs
        self.model = model
        self.backendURL = backendURL
        self.launch = launch
        self.onOpenGarage = onOpenGarage
        let detent: JobSheetDetent
        if let screen = launch.jobSheetScreen {
            detent = screen.detent
        } else if launch.opensCitationPage {
            detent = .half
        } else {
            detent = .collapsed
        }
        _demoImages = State(initialValue: DemoImageStore())
        _presentedViewer = State(initialValue: nil)
        _presentedCitation = State(initialValue: nil)
        _jobSheet = State(initialValue: JobSheetViewModel(detent: detent))
        _lookBackPath = State(initialValue: [])
        _lookBackGeneration = State(initialValue: 0)
        _topChromeHeight = State(initialValue: 0)
        _windowHeight = State(initialValue: 0)
        _topSafeArea = State(initialValue: 0)
        _bottomSafeArea = State(initialValue: 0)
    }

    private var configuration: ChatClientConfiguration {
        ChatClientConfiguration(baseURL: backendURL)
    }

    var body: some View {
        NavigationStack(path: $lookBackPath) {
            messageList
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        if showPaperHeader {
                            paperHeader
                        }
                        if let notice = jobs.notice {
                            Text(notice)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .accessibilityIdentifier("jobs.storageNotice")
                        }
                        if launch.showDemoChrome, model.isDemoMode {
                            DemoModeChrome(
                                model: model,
                                store: demoImages,
                                configuration: configuration
                            )
                        }
                    }
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: TopChromeHeightKey.self, value: proxy.size.height)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomBar
                        .hidden()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .navigationTitle("Sidekick")
                .navigationBarTitleDisplayMode(.inline)
                // iOS 26 Liquid Glass on ToolbarItem survived .buttonStyle(.plain)
                // and opaque UINavigationBarAppearance. Garage is plain text here.
                .toolbar(.hidden, for: .navigationBar)
                .background(JobSheetChrome.screen)
                .navigationDestination(for: LookBackVisit.self) { visit in
                    lookBackDestination(visit)
                        .id(visit)
                }
        }
        .onPreferenceChange(TopChromeHeightKey.self) { topChromeHeight = $0 }
        .overlay {
            ZStack(alignment: .bottom) {
                jobSheetScrim
                if lookBackPath.isEmpty {
                    bottomBar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // Container (home indicator / status bar) so the sheet is edge to edge.
            // Do not ignore `.keyboard` — that covered the composer while typing.
            .ignoresSafeArea(.container)
        }
        .background(JobSheetChrome.screen)
        .background {
            WindowSafeAreaProbe { height, top, bottom in
                windowHeight = height
                topSafeArea = top
                bottomSafeArea = bottom
            }
        }
        .statusBarHidden(false)
        .persistentSystemOverlays(.visible)
        .citationSheet($presentedCitation)
        .task(id: demoLoadToken) {
            guard model.isDemoMode || launch.opensJobSheet || launch.opensLookBack || launch.showDemoChrome else { return }
            await demoImages.load(from: configuration)
            if model.isDemoMode, model.selectedDemoPhotoID == nil {
                model.selectedDemoPhotoID = demoImages.catalog?.defaultPhotoID
                    ?? DemoLaunchOptions.defaultPhotoID
            }
        }
    }

    private var demoLoadToken: String {
        "\(model.isDemoMode)-\(launch.opensJobSheet)-\(launch.opensLookBack)-\(launch.showDemoChrome)"
    }

    /// Dim stays full-bleed. Hits do not: the paper header sits under this overlay,
    /// and a full-screen hit target made Jobs untappable once a sheet was at half.
    @ViewBuilder
    private var jobSheetScrim: some View {
        if presentedJob != nil, JobSheetLayout.scrimOpacity(detent: jobSheet.detent) > 0 {
            let opacity = JobSheetLayout.scrimOpacity(detent: jobSheet.detent)
            ZStack(alignment: .top) {
                Color.black
                    .opacity(opacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: headerPassThrough)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: scrimHitHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { jobSheet.close() }
                        .accessibilityIdentifier("jobSheet.dim")
                        .accessibilityLabel("Close job sheet")
                        .accessibilityAddTraits(.isButton)
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea()
            }
            .animation(.easeInOut(duration: 0.22), value: jobSheet.detent)
        }
    }

    /// Window-top to the bottom of the paper header. Zero when the header is hidden (full sheet).
    private var headerPassThrough: CGFloat {
        guard showPaperHeader else { return 0 }
        // A full-screen GeometryReader reading is not the header. Fall back to one bar.
        let chrome = topChromeHeight > 0 && topChromeHeight < 320 ? topChromeHeight : 44
        return topSafeArea + chrome
    }

    /// The dimmed band between the header and the sheet. Its center stays on chat, so a scrim tap still collapses.
    private var scrimHitHeight: CGFloat {
        guard windowHeight > 0 else { return 200 }
        let sheetTop = CGFloat(JobSheetLayout.originY(
            detent: jobSheet.detent,
            screenHeight: Double(windowHeight),
            topSafeArea: Double(topSafeArea),
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        ))
        return max(sheetTop - headerPassThrough, 44)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty && !model.isLoading {
                        Text(JobsCopy.emptyChat)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.messages, id: \.id) { message in
                        MessageBubble(
                            message: message,
                            demoContext: demoContext(for: message),
                            onOpenHighlight: { presentViewer(for: message) },
                            onOpenCitation: { presentedCitation = $0 }
                        )
                            .id(message.id)
                    }
                    if model.isLoading {
                        loadingRow
                            .id(Self.loadingID)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat.messageList")
            .allowsHitTesting(presentedJob == nil || !jobSheet.blocksChat)
            .onAppear {
                scrollToEnd(proxy)
                presentLaunchViewerIfNeeded()
                presentLaunchCitationIfNeeded()
                presentLaunchLookBackIfNeeded()
            }
            .onChange(of: demoImages.images.count) { _, _ in
                refreshLaunchViewerImage()
            }
            .fullScreenCover(isPresented: launchViewerPresented) {
                if let session = presentedViewer {
                    HighlightViewerView(
                        presentation: session.presentation,
                        image: session.image,
                        referenceImage: session.referenceImage,
                        geometry: session.geometry,
                        attribution: session.attribution,
                        shareAlike: session.shareAlike,
                        onYes: session.onYes,
                        onNotThis: session.onNotThis
                    )
                    .modifier(
                        AccessibilityLaunchModifier(enabled: launch.prefersAccessibilitySize)
                    )
                }
            }
            .onChange(of: model.messages.count) { _, _ in
                scrollToEnd(proxy)
            }
            .onChange(of: model.isLoading) { _, _ in
                scrollToEnd(proxy)
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Waiting for a reply")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Waiting for a reply")
    }

    private var presentedJob: JobSheetState? {
        guard lookBackPath.isEmpty else { return nil }
        return model.sheetJob
    }

    private var showPaperHeader: Bool {
        lookBackPath.isEmpty && !(presentedJob != nil && jobSheet.detent == .full)
    }

    /// Paper header, not a toolbar item. iOS 26 draws Liquid Glass behind toolbar buttons.
    private var paperHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    garageButton
                    Spacer(minLength: 0)
                    newJobButton
                    jobsButton
                    scanLogButton
                    demoToggle
                }
            } else {
                ZStack {
                    Text("Sidekick")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("chat.title")
                    HStack {
                        HStack(spacing: 12) {
                            garageButton
                            jobsButton
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 12) {
                            newJobButton
                            scanLogButton
                            demoToggle
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity)
        .background(JobSheetChrome.screen)
    }

    @ViewBuilder
    private var garageButton: some View {
        if let onOpenGarage {
            Button("Garage", action: onOpenGarage)
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize()
                .accessibilityIdentifier("chat.garage")
        }
    }

    private var newJobButton: some View {
        Button {
            model.startNewJob()
            jobSheet.setDetent(.collapsed)
        } label: {
            Text(JobsCopy.newJob)
        }
        .buttonStyle(.plain)
        .font(.body)
        .foregroundStyle(.primary)
        .fixedSize()
        .disabled(model.target == .newJob)
        .accessibilityIdentifier("chat.newJob")
    }

    private var jobsButton: some View {
        Button {
            showLookBack(.jobHistory)
        } label: {
            lookBackHeaderLabel(title: JobHistoryCopy.title, systemImage: "list.bullet.rectangle")
        }
        .buttonStyle(.plain)
        .font(.body)
        .foregroundStyle(.primary)
        .fixedSize()
        .accessibilityIdentifier("chat.jobs")
        .accessibilityLabel(JobHistoryCopy.title)
    }

    private var scanLogButton: some View {
        Button {
            showLookBack(.scanLog)
        } label: {
            lookBackHeaderLabel(title: ScanLogCopy.title, systemImage: "square.grid.2x2")
        }
        .buttonStyle(.plain)
        .font(.body)
        .foregroundStyle(.primary)
        .fixedSize()
        .accessibilityLabel(ScanLogCopy.title)
        .accessibilityIdentifier("chat.scanLog")
    }

    @ViewBuilder
    private func lookBackHeaderLabel(title: String, systemImage: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .imageScale(.medium)
                // Keep icons compact so Garage + Jobs + Scan log stay inside the window.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityHidden(true)
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    private var demoToggle: some View {
        if launch.showDemoChrome {
            Button(model.isDemoMode ? "Demo on" : "Demo mode") {
                model.isDemoMode.toggle()
            }
            .buttonStyle(.plain)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize()
            .accessibilityIdentifier("demo.toggle")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if presentedJob == nil || !jobSheet.blocksChat {
                composerChrome
            }
            if let job = presentedJob {
                JobSheetView(
                    job: job,
                    sheet: jobSheet,
                    onEdit: { jobs.edit(job.id, $0) },
                    image: jobPhoto,
                    attribution: jobAttribution,
                    shareAlike: jobShareAlike,
                    flags: launch.featureFlags,
                    screenHeight: windowHeight,
                    topSafeArea: topSafeArea,
                    bottomChromeInset: launch.showDemoChrome
                        ? max(bottomSafeArea, CGFloat(JobSheetLayout.demoTabChromeHeight))
                        : 0,
                    onOpenHighlight: presentJobViewer,
                    onAttachPhoto: attachDemoPhotoToJob,
                    onOpenCitation: { presentedCitation = $0 }
                )
            }
        }
    }

    @ViewBuilder
    private var composerChrome: some View {
        VStack(spacing: 0) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.15))
                    .accessibilityIdentifier("chat.error")
                    .accessibilityLabel("Error. \(errorMessage)")
            }
            composer
        }
        .background(JobSheetChrome.screen)
        .padding(
            .bottom,
            CGFloat(
                JobSheetLayout.composerHomeInset(
                    hasJob: presentedJob != nil,
                    bottomSafeArea: Double(bottomSafeArea)
                )
            )
        )
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let job = presentedJob, !job.hasPhoto {
                Button(action: attachDemoPhotoToJob) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.attach")
                .accessibilityLabel(JobSheetCopy.attach)
                .accessibilityHint(JobSheetCopy.attachHint)
            }
            TextField("Describe the problem", text: $model.composerText, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(JobSheetChrome.paper)
                        .overlay {
                            Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                        }
                }
                .accessibilityIdentifier("chat.composer")

            Button {
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(!model.canSend)
            .accessibilityIdentifier("chat.send")
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if model.isLoading {
            proxy.scrollTo(Self.loadingID, anchor: .bottom)
        } else if let last = model.messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private static let loadingID = "chat-loading"

    private func demoContext(for message: Message) -> DemoAnswerContext? {
        guard model.isDemoMode else { return nil }
        let highlight: HighlightRef?
        if case let .assistant(assistant) = message, case let .found(found) = assistant.answer {
            highlight = found.highlight
        } else {
            highlight = nil
        }
        let photoID = highlight?.bayPhotoID.rawValue ?? model.selectedDemoPhotoID
        let photoInfo = demoImages.catalog?.photos.first { $0.photoID == photoID }
        let display = model.effectiveDisplay(for: message.id, highlight: highlight)
        return DemoAnswerContext(
            isDemoMode: true,
            photo: photoID.flatMap { demoImages.images[$0] },
            attribution: photoInfo?.attribution ?? "Demo data. Not Zeke's truck.",
            shareAlike: photoInfo?.shareAlike ?? false,
            style: model.highlightStyle,
            highlight: highlight,
            display: display,
            flags: launch.featureFlags,
            onYes: {
                model.applyDemoConfirm(messageID: message.id, decision: .yes)
                if let photoID, let partID = highlight?.partID.rawValue {
                    postDemoFeedback(
                        configuration: configuration,
                        photoID: photoID,
                        partID: partID,
                        action: .yes
                    )
                }
            },
            onNotThis: {
                model.applyDemoConfirm(messageID: message.id, decision: .notThis)
                if let photoID, let partID = highlight?.partID.rawValue {
                    postDemoFeedback(
                        configuration: configuration,
                        photoID: photoID,
                        partID: partID,
                        action: .notThis
                    )
                }
            }
        )
    }

    private func presentViewer(for message: Message) {
        guard let demo = demoContext(for: message), let image = demo.photo else { return }
        let presentation = demo.viewerPresentation
        let photoID = demo.highlight?.bayPhotoID.rawValue ?? presentation.photoID
        let partID = demo.highlight?.partID.rawValue ?? presentation.partID
        presentedViewer = HighlightViewerSession(
            presentation: presentation,
            image: image,
            referenceImage: presentation.referencePhotoID.flatMap { demoImages.images[$0] },
            geometry: presentation.showsOutline
                ? (demo.highlight?.geometry ?? DemoOutlineCatalog.geometry(
                    photoID: presentation.kind == .reference
                        ? (presentation.outlinePhotoID)
                        : photoID,
                    partID: partID
                ))
                : nil,
            attribution: demo.attribution,
            shareAlike: demo.shareAlike,
            onYes: demo.onYes,
            onNotThis: demo.onNotThis
        )
    }

    private func presentLaunchViewerIfNeeded() {
        guard presentedViewer == nil, let screen = launch.screen else { return }
        let presentation = HighlightViewerPresentation.resolve(
            source: screen.source,
            flags: launch.featureFlags,
            photoID: launch.resolvedPhotoID,
            partID: launch.partID
        )
        presentedViewer = HighlightViewerSession(
            presentation: presentation,
            image: demoImages.images[launch.resolvedPhotoID] ?? HighlightPlaceholderImage.make(),
            referenceImage: presentation.referencePhotoID.flatMap { demoImages.images[$0] },
            geometry: HighlightViewerScript.geometry(
                photoID: presentation.outlinePhotoID,
                partID: presentation.partID,
                showingOutline: presentation.showsOutline
            ),
            attribution: "Demo data. Not Zeke's truck.",
            shareAlike: false
        )
    }

    private var launchViewerPresented: Binding<Bool> {
        Binding(
            get: { presentedViewer != nil },
            set: { if !$0 { presentedViewer = nil } }
        )
    }

    private func refreshLaunchViewerImage() {
        guard launch.screen != nil, var session = presentedViewer else { return }
        if let image = demoImages.images[launch.resolvedPhotoID] {
            session.image = image
        }
        if let referenceID = session.presentation.referencePhotoID,
           let reference = demoImages.images[referenceID] {
            session.referenceImage = reference
        }
        presentedViewer = session
    }

    private func presentLaunchCitationIfNeeded() {
        guard launch.opensCitationPage, presentedCitation == nil else { return }
        presentedCitation = HighlightViewerScript.fixtureCitation
    }

    private func presentLaunchLookBackIfNeeded() {
        guard lookBackPath.isEmpty, let screen = launch.lookBackScreen else { return }
        showLookBack(screen)
    }

    /// Replace the stack with a new visit. An equal `LookBackScreen` is the same
    /// destination, so a second Jobs tap kept the old list and its scroll offset.
    /// The newest row then sat above the viewport and was not in the accessibility tree.
    private func showLookBack(_ screen: LookBackScreen) {
        lookBackGeneration += 1
        lookBackPath = [LookBackVisit(screen: screen, generation: lookBackGeneration)]
    }

    @ViewBuilder
    private func lookBackDestination(_ visit: LookBackVisit) -> some View {
        switch visit.screen {
        case .jobHistory:
            JobHistoryView(
                jobs: jobs.jobs,
                now: Date(),
                store: demoImages,
                configuration: configuration,
                flags: launch.featureFlags,
                visitGeneration: visit.generation,
                onOpenJob: openHistoryJob
            )
            .modifier(AccessibilityLaunchModifier(enabled: launch.prefersAccessibilitySize))
        case .scanLog:
            ScanLogView(
                store: demoImages,
                configuration: configuration,
                flags: launch.featureFlags,
                onOpenCell: openScanCell
            )
            .modifier(AccessibilityLaunchModifier(enabled: launch.prefersAccessibilitySize))
        }
    }

    private func openHistoryJob(_ id: JobID) {
        lookBackPath = []
        model.open(id)
        jobSheet.setDetent(.half)
    }

    private func openScanCell(_ entry: ScanLogEntry) {
        let presentation = entry.presentation(flags: launch.featureFlags)
        let photoInfo = demoImages.catalog?.photos.first { $0.photoID == entry.photoID }
        presentedViewer = HighlightViewerSession(
            presentation: presentation,
            image: demoImages.images[entry.photoID] ?? HighlightPlaceholderImage.make(),
            referenceImage: presentation.referencePhotoID.flatMap { demoImages.images[$0] },
            geometry: entry.geometry(flags: launch.featureFlags),
            attribution: photoInfo?.attribution ?? "Demo data. Not Zeke's truck.",
            shareAlike: photoInfo?.shareAlike ?? false
        )
    }

    private func presentJobViewer() {
        guard let job = presentedJob, job.hasPhoto else { return }
        let presentation = HighlightViewerPresentation.resolve(
            source: HighlightViewerState.fromDemo(
                display: job.highlight?.display,
                highlight: job.highlight
            ),
            flags: launch.featureFlags,
            photoID: job.photoID ?? launch.resolvedPhotoID,
            partID: job.highlight?.partID.rawValue ?? launch.partID
        )
        presentedViewer = HighlightViewerSession(
            presentation: presentation,
            image: jobPhoto ?? HighlightPlaceholderImage.make(),
            referenceImage: presentation.referencePhotoID.flatMap { demoImages.images[$0] },
            geometry: presentation.showsOutline
                ? (job.highlight?.geometry ?? HighlightViewerScript.geometry(
                    photoID: presentation.outlinePhotoID,
                    partID: presentation.partID,
                    showingOutline: true
                ))
                : nil,
            attribution: jobAttribution,
            shareAlike: jobShareAlike
        )
    }

    private func attachDemoPhotoToJob() {
        guard let job = model.sheetJob else { return }
        let photoID = model.activeDemoPhotoID
            ?? (launch.opensJobSheet ? launch.resolvedPhotoID : nil)
            ?? DemoLaunchOptions.defaultPhotoID
        jobs.edit(job.id, .attachDemoPhoto(photoID: photoID))
        if model.isDemoMode, model.selectedDemoPhotoID == nil {
            model.selectedDemoPhotoID = photoID
        }
    }

    private var jobPhoto: UIImage? {
        guard let photoID = presentedJob?.photoID else { return nil }
        return demoImages.images[photoID]
    }

    private var jobPhotoInfo: DemoPhotoInfo? {
        guard let photoID = presentedJob?.photoID else { return nil }
        return demoImages.catalog?.photos.first { $0.photoID == photoID }
    }

    private var jobAttribution: String {
        jobPhotoInfo?.attribution ?? "Demo data. Not Zeke's truck."
    }

    private var jobShareAlike: Bool {
        jobPhotoInfo?.shareAlike ?? false
    }
}

private struct HighlightViewerSession {
    let id = UUID()
    var presentation: HighlightViewerPresentation
    var image: UIImage
    var referenceImage: UIImage?
    var geometry: HighlightGeometry?
    var attribution: String
    var shareAlike: Bool
    var onYes: (() -> Void)?
    var onNotThis: (() -> Void)?
}

/// User turns stay text bubbles. Assistant turns are answer cards.
private struct MessageBubble: View {
    let message: Message
    var demoContext: DemoAnswerContext?
    var onOpenHighlight: (() -> Void)?
    var onOpenCitation: ((Citation) -> Void)?

    var body: some View {
        switch message {
        case let .user(user):
            HStack(alignment: .bottom, spacing: 0) {
                Spacer(minLength: 32)
                Text(user.text)
                    .font(.body)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                .background(
                    Color.black,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .accessibilityLabel("You said \(user.text)")
                .accessibilityIdentifier("chat.userMessage")
            }
        case let .assistant(assistant):
            HStack(alignment: .top, spacing: 0) {
                AnswerCardView(
                    content: AnswerCardContent(answer: assistant.answer),
                    messageID: assistant.id,
                    demoContext: demoContext,
                    onOpenHighlight: onOpenHighlight,
                    onOpenCitation: onOpenCitation
                )
                Spacer(minLength: 32)
            }
        }
    }
}

@MainActor
private enum ChatScreenPreview {
    static func host(
        isDemoMode: Bool = false,
        selectedDemoPhotoID: String? = nil,
        client: any ChatClient = IdleChatClient(),
        includeAnswer: Bool = true,
        composerText: String = "Still doing it.",
        sendOnAppear: Bool = false
    ) -> ChatPreviewHost {
        let jobID = JobID(rawValue: "preview-job")!
        var messages: [Message] = [
            .user(
                UserMessage(
                    id: MessageID(rawValue: "preview-user")!,
                    text: "Rough idle after cold start."
                )!
            ),
        ]
        if includeAnswer {
            messages.append(
                .assistant(
                    AssistantMessage(
                        id: MessageID(rawValue: "preview-assistant")!,
                        answer: .found(
                            FoundAnswer(
                                text: "This is a fixture-only reply with no manual citations."
                            )!
                        )
                    )
                )
            )
        }
        let job = JobSheetState(
            id: jobID,
            title: "Rough idle after",
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            conversation: Conversation(
                id: ConversationID(rawValue: jobID.rawValue)!,
                messages: messages
            ),
            steps: includeAnswer ? JobSheetCopy.steps(photoID: DemoLaunchOptions.defaultPhotoID) : []
        )
        let jobs = JobsModel(source: .memory([job]), client: client)
        let chat = ChatViewModel(
            jobs: jobs,
            target: .job(jobID),
            composerText: composerText,
            isDemoMode: isDemoMode,
            selectedDemoPhotoID: selectedDemoPhotoID
        )
        return ChatPreviewHost(jobs: jobs, chat: chat, sendOnAppear: sendOnAppear)
    }
}

private struct ChatPreviewHost: View {
    @State private var jobs: JobsModel
    @State private var chat: ChatViewModel
    var sendOnAppear: Bool

    init(jobs: JobsModel, chat: ChatViewModel, sendOnAppear: Bool = false) {
        _jobs = State(initialValue: jobs)
        _chat = State(initialValue: chat)
        self.sendOnAppear = sendOnAppear
    }

    var body: some View {
        ChatScreen(jobs: jobs, model: chat, onOpenGarage: {})
            .task {
                if sendOnAppear {
                    await chat.send()
                }
            }
    }
}

private struct IdleChatClient: ChatClient {
    func send(_ conversation: Conversation, demoPhotoID: String?) async throws -> Answer {
        _ = conversation
        _ = demoPhotoID
        throw ChatClientError.offline
    }
}

private struct HangingChatClient: ChatClient {
    func send(_ conversation: Conversation, demoPhotoID: String?) async throws -> Answer {
        _ = conversation
        _ = demoPhotoID
        try await Task.sleep(for: .seconds(3_600))
        throw ChatClientError.offline
    }
}

#Preview("Light") {
    ChatScreenPreview.host()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ChatScreenPreview.host()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility XL") {
    ChatScreenPreview.host()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Accessibility XXXL") {
    ChatScreenPreview.host()
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Loading") {
    ChatScreenPreview.host(client: HangingChatClient(), includeAnswer: false, sendOnAppear: true)
}

#Preview("Error") {
    ChatScreenPreview.host(client: IdleChatClient(), sendOnAppear: true)
}

#Preview("Demo mode") {
    ChatScreenPreview.host(
        isDemoMode: true,
        selectedDemoPhotoID: DemoLaunchOptions.defaultPhotoID
    )
    .preferredColorScheme(.light)
}
