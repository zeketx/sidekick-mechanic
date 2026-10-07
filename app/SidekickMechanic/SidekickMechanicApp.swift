import SidekickCore
import SwiftUI
import UIKit

@main
struct SidekickMechanicApp: App {
    private static let launch = DemoLaunchOptions.parse()
    @State private var chatModel = SidekickMechanicApp.makeChatModel()

    init() {
        Self.installOpaqueChrome()
    }

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

    /// Solid #F4F4F4 bars. iOS 26 glass capsules stay off the v1 chrome.
    private static func installOpaqueChrome() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = JobSheetChrome.screenUIColor
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor.label]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().isTranslucent = false

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = JobSheetChrome.screenUIColor
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().isTranslucent = false
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if Self.launch.showDemoChrome {
                    TabView {
                        ChatScreen(model: chatModel, launch: Self.launch)
                            .tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }
                        ReadingsTab()
                            .tabItem { Label("Readings", systemImage: "gauge.with.dots.needle.33percent") }
                    }
                } else {
                    ChatScreen(model: chatModel, launch: Self.launch)
                }
            }
            .background(JobSheetChrome.screen)
            .statusBarHidden(false)
            .persistentSystemOverlays(.visible)
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
