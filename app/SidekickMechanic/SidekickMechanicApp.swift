import SidekickCore
import SwiftUI

@main
struct SidekickMechanicApp: App {
    private static let launch = DemoLaunchOptions.parse()
    @State private var chatModel = SidekickMechanicApp.makeChatModel()

    private static func makeChatModel() -> ChatViewModel {
        let launch = Self.launch
        let jobLaunch = launch.opensJobSheet
        return ChatViewModel(
            conversationID: ConversationID(rawValue: UUID().uuidString)!,
            messages: jobLaunch ? JobSheetScript.messages : [],
            composerText: launch.enablesDemoMode && !jobLaunch ? launch.cannedQuestion : "",
            isDemoMode: launch.enablesDemoMode,
            selectedDemoPhotoID: launch.enablesDemoMode ? launch.resolvedPhotoID : nil,
            highlightStyle: launch.style ?? .outline,
            client: LiveChatClient(configuration: ChatClientConfiguration(baseURL: AppConfig.backendURL))
        )
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                ChatScreen(model: chatModel, launch: Self.launch)
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }
                ReadingsTab()
                    .tabItem { Label("Readings", systemImage: "gauge.with.dots.needle.33percent") }
            }
        }
    }
}

/// Backend base URL from Info.plist (`SIDEKICK_BACKEND_URL` build setting). Defaults to localhost for the Simulator.
enum AppConfig {
    static var backendURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "SidekickBackendURL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        return URL(string: "http://localhost:8000")!
    }
}

/// Starts the bundled telemetry simulator on first appearance.
private struct ReadingsTab: View {
    @State private var model: ReadingsViewModel?

    var body: some View {
        Group {
            if let model {
                ReadingsScreen(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            guard model == nil else { return }
            do {
                let created = try ReadingsViewModel.bundled(clock: WallClockTelemetryClock())
                model = created
                await created.start()
            } catch {
                assertionFailure("bundled telemetry scenarios failed to load: \(error)")
            }
        }
    }
}
