import SidekickCore
import SwiftUI

/// Message list and composer. Assistant replies use `AnswerCardView`.
struct ChatScreen: View {
    @Bindable var model: ChatViewModel
    var backendURL: URL = AppConfig.backendURL
    @State private var demoImages = DemoImageStore()

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
                            demoContext: demoContext(for: message)
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
            .onAppear { scrollToEnd(proxy) }
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

    private var bottomBar: some View {
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

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
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
}

/// User turns stay text bubbles. Assistant turns are answer cards.
private struct MessageBubble: View {
    let message: Message
    var demoContext: DemoAnswerContext?

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
                    demoContext: demoContext
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
            selectedDemoPhotoID: "hrymx-2jz-ge-25308847029"
        )
    )
    .preferredColorScheme(.light)
}
