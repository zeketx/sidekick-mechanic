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
        let stripped = PageExcerpt.stripControlCharacters(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }
}

/// Page-text cleanup for Go deeper. Matches `backend/go_deeper.py`.
///
/// Search is a character walk, not `range(of:)` / StringProcessing: Linux Swift
/// 6.4 segfaults compiling case-insensitive `range(of:)` in this module.
public enum PageExcerpt {
    public static let characterLimit = 300

    /// Drop C0 controls except newline and tab.
    public static func stripControlCharacters(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value == 9 || value == 10 || (value >= 32 && value != 127) {
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    /// One to three sentences around `snippet`, capped on a word boundary.
    /// Nil when the snippet is missing from the page.
    public static func aroundSnippet(
        pageText: String,
        snippet: String,
        limit: Int = characterLimit
    ) -> String? {
        let page = collapsed(stripControlCharacters(pageText))
        let needle = collapsed(stripControlCharacters(snippet))
        guard !page.isEmpty, !needle.isEmpty else { return nil }
        guard let pageStart = firstMatchStart(in: page, of: needle) else {
            return nil
        }
        let sentences = splitSentences(page)
        if let matched = firstSentenceIndex(sentences, containing: needle) {
            let sentence = sentences[matched]
            if sentence.count > limit {
                if let start = firstMatchStart(in: sentence, of: needle) {
                    return cap(String(sentence[start...]), limit: limit)
                }
                return cap(sentence, limit: limit)
            }
            var pieces: [String] = [sentence]
            var index = matched + 1
            while index < sentences.count, pieces.count < 3 {
                let next = sentences[index]
                let joined = (pieces + [next]).joined(separator: " ")
                if joined.count > limit { break }
                pieces.append(next)
                index += 1
            }
            return cap(pieces.joined(separator: " "), limit: limit)
        }
        return cap(String(page[pageStart...]), limit: limit)
    }

    private static func collapsed(_ text: String) -> String {
        var words: [String] = []
        var current = ""
        for character in text {
            if character.isWhitespace {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words.joined(separator: " ")
    }

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "." || character == "!" || character == "?" {
                let trimmed = trimSpaces(current)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let trailing = trimSpaces(current)
        if !trailing.isEmpty { sentences.append(trailing) }
        return sentences
    }

    private static func firstSentenceIndex(_ sentences: [String], containing needle: String) -> Int? {
        var index = 0
        while index < sentences.count {
            if firstMatchStart(in: sentences[index], of: needle) != nil {
                return index
            }
            index += 1
        }
        return nil
    }

    /// Case-insensitive ASCII substring start. Manuals are ASCII-heavy.
    private static func firstMatchStart(in haystack: String, of needle: String) -> String.Index? {
        let hayChars = Array(haystack)
        let needleChars = Array(needle)
        let needleCount = needleChars.count
        guard needleCount > 0, hayChars.count >= needleCount else { return nil }
        let foldedNeedle = needleChars.map(foldASCII)
        let lastStart = hayChars.count - needleCount
        var start = 0
        while start <= lastStart {
            var offset = 0
            var matched = true
            while offset < needleCount {
                if foldASCII(hayChars[start + offset]) != foldedNeedle[offset] {
                    matched = false
                    break
                }
                offset += 1
            }
            if matched {
                return haystack.index(haystack.startIndex, offsetBy: start)
            }
            start += 1
        }
        return nil
    }

    private static func foldASCII(_ character: Character) -> Character {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            return character
        }
        let value = scalar.value
        if value >= 65 && value <= 90 {
            return Character(Unicode.Scalar(value + 32)!)
        }
        return character
    }

    private static func cap(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let prefix = String(text.prefix(limit))
        var clipped = prefix
        if let lastSpace = lastIndex(ofSpaceIn: prefix) {
            clipped = String(prefix[..<lastSpace])
        }
        clipped = rstripPunctuation(clipped)
        if clipped.isEmpty {
            clipped = trimSpaces(prefix)
        }
        return clipped + "…"
    }

    private static func lastIndex(ofSpaceIn text: String) -> String.Index? {
        var found: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == " " {
                found = index
            }
            index = text.index(after: index)
        }
        return found
    }

    private static func rstripPunctuation(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let previous = text.index(before: end)
            let ch = text[previous]
            if ch == "." || ch == "," || ch == ";" || ch == ":" || ch == " " {
                end = previous
            } else {
                break
            }
        }
        return String(text[..<end])
    }

    private static func trimSpaces(_ text: String) -> String {
        var start = text.startIndex
        var end = text.endIndex
        while start < end, text[start] == " " {
            start = text.index(after: start)
        }
        while end > start {
            let previous = text.index(before: end)
            if text[previous] == " " {
                end = previous
            } else {
                break
            }
        }
        return String(text[start..<end])
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
        tools: "You need a flashlight."
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
    func goDeeper(docID: DocumentID, page: PageNumber, snippet: String) async throws -> GoDeeper
}

public struct CannedGoDeeperSource: GoDeeperSource {
    public init() {}

    public func goDeeper(docID: DocumentID, page: PageNumber, snippet: String) async throws -> GoDeeper {
        _ = snippet
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

    public func goDeeper(docID: DocumentID, page: PageNumber, snippet: String) async throws -> GoDeeper {
        _ = snippet
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

    public func goDeeper(docID: DocumentID, page: PageNumber, snippet: String) async throws -> GoDeeper {
        guard let remoteURL = ManualPageLocation.goDeeperURL(
            baseURL: configuration.baseURL,
            docID: docID,
            page: page,
            snippet: snippet
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

    public func goDeeper(docID: DocumentID, page: PageNumber, snippet: String) async throws -> GoDeeper {
        if docID.rawValue.hasPrefix("FAKE-DOC") {
            return try await canned.goDeeper(docID: docID, page: page, snippet: snippet)
        }
        return try await remote.goDeeper(docID: docID, page: page, snippet: snippet)
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
