import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Everyday-English block under a cited manual page. JSON keys are snake_case.
/// Empty sections are omitted. Copy is grounded only in that page.
public struct GoDeeper: Hashable, Sendable {
    public var howItWorks: String?
    public var whatToTest: String?
    public var howToTest: String?
    public var tools: String?

    public init(
        howItWorks: String? = nil,
        whatToTest: String? = nil,
        howToTest: String? = nil,
        tools: String? = nil
    ) {
        self.howItWorks = Self.present(howItWorks)
        self.whatToTest = Self.present(whatToTest)
        self.howToTest = Self.present(howToTest)
        self.tools = Self.present(tools)
    }

    public var hasContent: Bool {
        howItWorks != nil || whatToTest != nil || howToTest != nil || tools != nil
    }

    /// Visible rows in order. Titles stay everyday words.
    public var sections: [(title: String, body: String)] {
        var rows: [(String, String)] = []
        if let howItWorks { rows.append(("How this works", howItWorks)) }
        if let whatToTest { rows.append(("What to test", whatToTest)) }
        if let howToTest { rows.append(("How to test it", howToTest)) }
        if let tools { rows.append(("Tools", tools)) }
        return rows
    }

    private static func present(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension GoDeeper: Codable {
    enum CodingKeys: String, CodingKey {
        case howItWorks = "how_it_works"
        case whatToTest = "what_to_test"
        case howToTest = "how_to_test"
        case tools
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            howItWorks: try container.decodeIfPresent(String.self, forKey: .howItWorks),
            whatToTest: try container.decodeIfPresent(String.self, forKey: .whatToTest),
            howToTest: try container.decodeIfPresent(String.self, forKey: .howToTest),
            tools: try container.decodeIfPresent(String.self, forKey: .tools)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(howItWorks, forKey: .howItWorks)
        try container.encodeIfPresent(whatToTest, forKey: .whatToTest)
        try container.encodeIfPresent(howToTest, forKey: .howToTest)
        try container.encodeIfPresent(tools, forKey: .tools)
    }
}

/// Canned Go deeper for fixture citations. Matches `backend/go_deeper.py`.
public enum CannedGoDeeper {
    public static let fakePageText = (
        "FAKE-PAGE: The fuse/relay box is the plastic box that holds the fuses "
            + "and relays for this engine bay. Look at the box. Check that the cover "
            + "is on and nothing looks burned. Open the cover and look. You need a "
            + "flashlight. No guessed numbers. Value FAKE-SPEC is not a real torque."
    )

    public static let fuseBox = GoDeeper(
        howItWorks: "The fuse/relay box is the plastic box that holds the fuses and relays for this engine bay.",
        whatToTest: "Look at the box. Check that the cover is on and nothing looks burned.",
        howToTest: "Open the cover and look.",
        tools: "A flashlight."
    )

    public static let fixturePage = GoDeeper(
        howItWorks: "This is a fixture page, not a real manual. It does not give a real procedure."
    )

    public static let diagramPage = GoDeeper(
        howItWorks: "This page is a wiring diagram. Read the labels on the page. I am not guessing pinouts or wire colors."
    )

    public static func content(docID: DocumentID, page: PageNumber) -> GoDeeper? {
        let raw = docID.rawValue
        guard raw.hasPrefix("FAKE-DOC") else { return nil }
        if raw == "FAKE-DOC-2JZ", page.rawValue == 999 {
            return fuseBox
        }
        return fixturePage
    }
}

public protocol GoDeeperSource: Sendable {
    func goDeeper(docID: DocumentID, page: PageNumber) async throws -> GoDeeper
}

public struct CannedGoDeeperSource: GoDeeperSource {
    public init() {}

    public func goDeeper(docID: DocumentID, page: PageNumber) async throws -> GoDeeper {
        guard let content = CannedGoDeeper.content(docID: docID, page: page) else {
            throw ManualPageError.missingPage
        }
        return content
    }
}

public struct FailingGoDeeperSource: GoDeeperSource {
    public var error: ManualPageError

    public init(error: ManualPageError) {
        self.error = error
    }

    public func goDeeper(docID: DocumentID, page: PageNumber) async throws -> GoDeeper {
        throw error
    }
}

public struct CachingGoDeeperSource: GoDeeperSource {
    private let configuration: ManualPageConfiguration
    private let http: any HTTPPerforming

    public init(configuration: ManualPageConfiguration, session: URLSession = .shared) {
        self.init(configuration: configuration, http: URLSessionHTTP(session: session))
    }

    init(configuration: ManualPageConfiguration, http: any HTTPPerforming) {
        self.configuration = configuration
        self.http = http
    }

    public func goDeeper(docID: DocumentID, page: PageNumber) async throws -> GoDeeper {
        guard let remoteURL = ManualPageLocation.goDeeperURL(
            baseURL: configuration.baseURL,
            docID: docID,
            page: page
        ) else {
            throw ManualPageError.missingPage
        }
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = configuration.requestTimeout
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            throw CachingManualPageSource.mapTransport(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ManualPageError.unavailable
        }
        if httpResponse.statusCode == 404 {
            throw ManualPageError.missingPage
        }
        guard httpResponse.statusCode == 200 else {
            throw ManualPageError.unavailable
        }
        do {
            return try JSONDecoder().decode(GoDeeper.self, from: data)
        } catch {
            throw ManualPageError.badImage
        }
    }
}

public struct CompositeGoDeeperSource: GoDeeperSource {
    private let canned: CannedGoDeeperSource
    private let remote: any GoDeeperSource

    public init(remote: any GoDeeperSource, canned: CannedGoDeeperSource = CannedGoDeeperSource()) {
        self.canned = canned
        self.remote = remote
    }

    public func goDeeper(docID: DocumentID, page: PageNumber) async throws -> GoDeeper {
        if docID.rawValue.hasPrefix("FAKE-DOC") {
            return try await canned.goDeeper(docID: docID, page: page)
        }
        return try await remote.goDeeper(docID: docID, page: page)
    }
}

public enum GoDeeperSources {
    public static func makeFromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> any GoDeeperSource {
        do {
            let configuration = try ManualPageConfiguration.load(
                environment: environment,
                infoDictionary: infoDictionary
            )
            return CompositeGoDeeperSource(
                remote: CachingGoDeeperSource(configuration: configuration)
            )
        } catch {
            return CompositeGoDeeperSource(remote: FailingGoDeeperSource(error: .notConfigured))
        }
    }
}

public struct CannedFakePageSource: ManualPageSource {
    public init() {}

    public func pageImage(docID: DocumentID, page: PageNumber) async throws -> ManualPageImage {
        guard docID.rawValue.hasPrefix("FAKE-DOC") else {
            throw ManualPageError.missingPage
        }
        return ManualPageImage(docID: docID, page: page, pngData: ManualPagePlaceholder.pngData())
    }
}

public struct CompositeManualPageSource: ManualPageSource {
    private let canned: CannedFakePageSource
    private let remote: any ManualPageSource

    public init(remote: any ManualPageSource, canned: CannedFakePageSource = CannedFakePageSource()) {
        self.canned = canned
        self.remote = remote
    }

    public func pageImage(docID: DocumentID, page: PageNumber) async throws -> ManualPageImage {
        if docID.rawValue.hasPrefix("FAKE-DOC") {
            return try await canned.pageImage(docID: docID, page: page)
        }
        return try await remote.pageImage(docID: docID, page: page)
    }
}
