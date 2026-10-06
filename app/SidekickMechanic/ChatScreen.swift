import SidekickCore
import SwiftUI
import UIKit

/// Message list and composer. Assistant replies use `AnswerCardView`.
struct ChatScreen: View {
    @Bindable var model: ChatViewModel
    var backendURL: URL = AppConfig.backendURL
    var launch: DemoLaunchOptions = DemoLaunchOptions.parse()
    @State private var demoImages = DemoImageStore()
    @State private var presentedViewer: HighlightViewerSession?
    @State private var jobSheet = JobSheetViewModel()

    private var configuration: ChatClientConfiguration {
        ChatClientConfiguration(baseURL: backendURL)
    }

    var body: some View {
        NavigationStack {
            messageList
                .safeAreaInset(edge: .top, spacing: 0) {
                    if model.isDemoMode {
                        DemoModeChrome(
                            model: model,
                            store: demoImages,
                            configuration: configuration
                        )
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomBar
                }
                .navigationTitle("Sidekick")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Toggle("Demo mode", isOn: $model.isDemoMode)
                            .accessibilityIdentifier("demo.toggle")
                    }
                }
                .background(.background)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty && !model.isLoading {
                        Text("Describe a problem.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.messages, id: \.id) { message in
                        MessageBubble(
                            message: message,
                            demoContext: demoContext(for: message),
                            onOpenHighlight: { presentViewer(for: message) }
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
            .accessibilityIdentifier("chat.messageList")
            .allowsHitTesting(!jobSheet.blocksChat)
            .overlay {
                if jobSheet.blocksChat {
                    Color.black.opacity(0.18)
                        .accessibilityIdentifier("jobSheet.dim")
                }
            }
            .onAppear {
                scrollToEnd(proxy)
                presentLaunchViewerIfNeeded()
                presentLaunchJobSheetIfNeeded()
                jobSheet.sync(from: model.messages, photoID: jobPhotoID)
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
                }
            }
            .onChange(of: model.messages.count) { _, _ in
                scrollToEnd(proxy)
                jobSheet.sync(from: model.messages, photoID: jobPhotoID)
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

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if !jobSheet.blocksChat {
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
                .background(.bar)
            }
            if jobSheet.hasJob {
                JobSheetView(
                    model: jobSheet,
                    image: jobPhoto,
                    attribution: jobAttribution,
                    shareAlike: jobShareAlike,
                    flags: launch.featureFlags,
                    onOpenHighlight: presentJobViewer,
                    onAttachPhoto: attachDemoPhotoToJob
                )
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if jobSheet.hasJob, jobSheet.job?.hasPhoto != true {
                Button(action: attachDemoPhotoToJob) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
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
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                }
                .accessibilityIdentifier("chat.composer")

            Button {
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
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

    private func presentLaunchJobSheetIfNeeded() {
        guard let screen = launch.jobSheetScreen else { return }
        jobSheet.applyLaunch(screen, photoID: launch.resolvedPhotoID)
    }

    private func presentJobViewer() {
        guard let job = jobSheet.job, job.hasPhoto else { return }
        let presentation = HighlightViewerPresentation.resolve(
            source: HighlightViewerState.fromDemo(
                display: job.highlight?.display,
                highlight: job.highlight
            ),
            flags: launch.featureFlags
        )
        presentedViewer = HighlightViewerSession(
            presentation: presentation,
            image: jobPhoto ?? HighlightPlaceholderImage.make(),
            geometry: presentation.showsOutline
                ? (job.highlight?.geometry ?? HighlightViewerScript.geometry(showingOutline: true))
                : nil,
            attribution: jobAttribution,
            shareAlike: jobShareAlike
        )
    }

    private func attachDemoPhotoToJob() {
        let photoID = jobPhotoID ?? DemoLaunchOptions.defaultPhotoID
        if !jobSheet.hasJob {
            jobSheet.sync(from: model.messages, photoID: photoID)
        }
        jobSheet.attachPhoto(photoID: photoID)
        if model.isDemoMode, model.selectedDemoPhotoID == nil {
            model.selectedDemoPhotoID = photoID
        }
    }

    private var jobPhotoID: String? {
        if launch.opensJobSheet {
            return model.selectedDemoPhotoID ?? launch.resolvedPhotoID
        }
        return model.activeDemoPhotoID
    }

    private var jobPhoto: UIImage? {
        guard let photoID = jobSheet.job?.photoID else { return nil }
        return demoImages.images[photoID]
    }

    private var jobPhotoInfo: DemoPhotoInfo? {
        guard let photoID = jobSheet.job?.photoID else { return nil }
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

    var body: some View {
        switch message {
        case let .user(user):
            HStack(alignment: .bottom, spacing: 0) {
                Spacer(minLength: 32)
                Text(user.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Color.accentColor.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
            .accessibilityLabel("You said \(user.text)")
        case let .assistant(assistant):
            HStack(alignment: .top, spacing: 0) {
                AnswerCardView(
                    content: AnswerCardContent(answer: assistant.answer),
                    messageID: assistant.id,
                    demoContext: demoContext,
                    onOpenHighlight: onOpenHighlight
                )
                Spacer(minLength: 32)
            }
        }
    }
}

@MainActor
private enum ChatScreenPreview {
    static func conversation(
        isLoading: Bool = false,
        errorMessage: String? = nil,
        isDemoMode: Bool = false,
        selectedDemoPhotoID: String? = nil
    ) -> ChatViewModel {
        ChatViewModel(
            conversationID: ConversationID(rawValue: "preview-conversation")!,
            messages: [
                .user(
                    UserMessage(
                        id: MessageID(rawValue: "preview-user")!,
                        text: "Rough idle after cold start."
                    )!
                ),
                .assistant(
                    AssistantMessage(
                        id: MessageID(rawValue: "preview-assistant")!,
                        answer: .found(
                            FoundAnswer(
                                text: "This is a fixture-only reply with no manual citations."
                            )!
                        )
                    )
                ),
            ],
            composerText: "Still doing it.",
            isLoading: isLoading,
            errorMessage: errorMessage,
            isDemoMode: isDemoMode,
            selectedDemoPhotoID: selectedDemoPhotoID,
            client: IdleChatClient()
        )
    }

    static func loading() -> ChatViewModel {
        ChatViewModel(
            conversationID: ConversationID(rawValue: "preview-conversation")!,
            messages: [
                .user(
                    UserMessage(
                        id: MessageID(rawValue: "preview-user")!,
                        text: "Rough idle after cold start."
                    )!
                ),
            ],
            composerText: "Still doing it.",
            isLoading: true,
            client: IdleChatClient()
        )
    }
}

private struct IdleChatClient: ChatClient {
    func send(_ conversation: Conversation, demoPhotoID: String?) async throws -> Answer {
        throw ChatClientError.offline
    }
}

#Preview("Light") {
    ChatScreen(model: ChatScreenPreview.conversation())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ChatScreen(model: ChatScreenPreview.conversation())
        .preferredColorScheme(.dark)
}

#Preview("Accessibility XL") {
    ChatScreen(model: ChatScreenPreview.conversation())
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Loading") {
    ChatScreen(model: ChatScreenPreview.loading())
}

#Preview("Error") {
    ChatScreen(model: ChatScreenPreview.conversation(
        errorMessage: ChatClientError.offline.userMessage
    ))
}

#Preview("Demo mode") {
    ChatScreen(
        model: ChatScreenPreview.conversation(
            isDemoMode: true,
            selectedDemoPhotoID: DemoLaunchOptions.defaultPhotoID
        )
    )
    .preferredColorScheme(.light)
}
