import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Rendered manual page. Bytes are a PNG of that document page, never a bundled asset.
public struct ManualPageImage: Equatable, Sendable {
    public let docID: DocumentID
    public let page: PageNumber
    public let pngData: Data

    public init(docID: DocumentID, page: PageNumber, pngData: Data) {
        self.docID = docID
        self.page = page
        self.pngData = pngData
    }

    public static func isPNG(_ data: Data) -> Bool {
        data.count >= pngSignature.count && data.prefix(pngSignature.count).elementsEqual(pngSignature)
    }

    static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
}

public enum ManualPageError: Error, Equatable, Sendable {
    case notConfigured
    case missingPage
    case unavailable
    case badImage

    public var message: String {
        switch self {
        case .notConfigured:
            "The backend URL is not configured for this build."
        case .missingPage:
            "This manual page is not available."
        case .unavailable:
            "Could not load the manual page. Check the connection and try again."
        case .badImage:
            "The manual page image was unreadable."
        }
    }
}

/// Loads one rendered page. Production reads a local cache, then the backend.
public protocol ManualPageSource: Sendable {
    func pageImage(docID: DocumentID, page: PageNumber) async throws -> ManualPageImage
}

/// Backend URL and on-device cache directory for rendered pages.
///
/// `GET {baseURL}/manuals/{doc_id}/pages/{page}.png`. Cache files live at
/// `{cache}/{doc_id}/{page}.png`, outside the repo. Set `SIDEKICK_PAGE_CACHE_DIR`
/// to override the cache. The backend URL is `SIDEKICK_BACKEND_URL` or Info.plist
/// `SidekickBackendURL`, same as chat.
public struct ManualPageConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var cacheDirectory: URL
    public var requestTimeout: TimeInterval

    public init(baseURL: URL, cacheDirectory: URL, requestTimeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.cacheDirectory = cacheDirectory
        self.requestTimeout = requestTimeout
    }

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary,
        defaultCacheDirectory: URL? = nil
    ) throws -> ManualPageConfiguration {
        let raw = environment["SIDEKICK_BACKEND_URL"]
            ?? infoDictionary?["SidekickBackendURL"] as? String
        guard let raw, let url = URL(string: raw), let scheme = url.scheme, !scheme.isEmpty,
              url.host != nil
        else {
            throw ManualPageError.notConfigured
        }
        let timeout = environment["SIDEKICK_BACKEND_TIMEOUT"].flatMap(TimeInterval.init) ?? 30
        let cache: URL
        if let override = environment["SIDEKICK_PAGE_CACHE_DIR"], !override.isEmpty {
            cache = URL(fileURLWithPath: override, isDirectory: true)
        } else if let defaultCacheDirectory {
            cache = defaultCacheDirectory
        } else {
            cache = platformCacheDirectory()
        }
        return ManualPageConfiguration(
            baseURL: url,
            cacheDirectory: cache,
            requestTimeout: timeout
        )
    }

    public static func platformCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("sidekick-manual-pages", isDirectory: true)
    }
}

public enum ManualPageSources {
    /// Caching backend source, or a failing source when the URL is not configured.
    public static func makeFromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> any ManualPageSource {
        do {
            let configuration = try ManualPageConfiguration.load(
                environment: environment,
                infoDictionary: infoDictionary
            )
            return CachingManualPageSource(configuration: configuration)
        } catch let error as ManualPageError {
            return FailingManualPageSource(error: error)
        } catch {
            return FailingManualPageSource(error: .notConfigured)
        }
    }
}

public struct FailingManualPageSource: ManualPageSource {
    public var error: ManualPageError

    public init(error: ManualPageError) {
        self.error = error
    }

    public func pageImage(docID: DocumentID, page: PageNumber) async throws -> ManualPageImage {
        throw error
    }
}

/// Cache first, then `GET` the page image and store the PNG.
public struct CachingManualPageSource: ManualPageSource {
    private let configuration: ManualPageConfiguration
    private let http: any HTTPPerforming

    public init(configuration: ManualPageConfiguration, session: URLSession = .shared) {
        self.init(configuration: configuration, http: URLSessionHTTP(session: session))
    }

    init(configuration: ManualPageConfiguration, http: any HTTPPerforming) {
        self.configuration = configuration
        self.http = http
    }

    public func pageImage(docID: DocumentID, page: PageNumber) async throws -> ManualPageImage {
        guard let fileURL = ManualPageLocation.cacheFile(
            cacheDirectory: configuration.cacheDirectory,
            docID: docID,
            page: page
        ), let remoteURL = ManualPageLocation.remoteURL(
            baseURL: configuration.baseURL,
            docID: docID,
            page: page
        ) else {
            throw ManualPageError.missingPage
        }
        if let cached = cachedPNG(at: fileURL) {
            return ManualPageImage(docID: docID, page: page, pngData: cached)
        }

        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        request.setValue("image/png", forHTTPHeaderField: "Accept")
        request.timeoutInterval = configuration.requestTimeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            throw Self.mapTransport(error)
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
        guard ManualPageImage.isPNG(data) else {
            throw ManualPageError.badImage
        }
        // A full disk should still show the page. The next open tries the cache, then the network.
        try? store(data, at: fileURL)
        return ManualPageImage(docID: docID, page: page, pngData: data)
    }

    private func cachedPNG(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard ManualPageImage.isPNG(data) else {
            // A non-PNG file would pin this page on a miss forever.
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return data
    }

    private func store(_ data: Data, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func mapTransport(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let pageError = error as? ManualPageError { return pageError }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? CancellationError() : ManualPageError.unavailable
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.code == NSURLErrorCancelled
                ? CancellationError()
                : ManualPageError.unavailable
        }
        return ManualPageError.unavailable
    }
}

/// Generated stand-in PNG for tests and SwiftUI previews. Not a manual page.
public enum ManualPagePlaceholder {
    public static let width = 64
    public static let height = 88

    public static func pngData() -> Data {
        StoredPNG.encode(width: width, height: height) { x, y in
            let border = x < 3 || y < 3 || x >= width - 3 || y >= height - 3
            if border {
                return (0x2C, 0x2C, 0x2C)
            }
            return (y / 8).isMultiple(of: 2) ? (0xF2, 0xF2, 0xF2) : (0xD8, 0xD8, 0xD8)
        }
    }
}

enum ManualPageLocation {
    static func cacheFile(cacheDirectory: URL, docID: DocumentID, page: PageNumber) -> URL? {
        guard let name = safeName(docID.rawValue) else { return nil }
        let root = cacheDirectory.standardizedFileURL
        let file = root
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("\(page.rawValue).png")
            .standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.path.hasPrefix(rootPath) else { return nil }
        return file
    }

    static func remoteURL(baseURL: URL, docID: DocumentID, page: PageNumber) -> URL? {
        guard let name = safeName(docID.rawValue) else { return nil }
        return baseURL
            .appendingPathComponent("manuals")
            .appendingPathComponent(name)
            .appendingPathComponent("pages")
            .appendingPathComponent("\(page.rawValue).png")
    }

    /// Document IDs become a single path component. `.` and `..` would escape the cache.
    static func safeName(_ name: String) -> String? {
        guard name != ".", name != "..", (1...128).contains(name.count) else { return nil }
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
        )
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return name
    }
}

/// RGB PNG using deflate stored blocks so the encoder needs no compression library.
enum StoredPNG {
    static func encode(
        width: Int,
        height: Int,
        pixel: (Int, Int) -> (UInt8, UInt8, UInt8)
    ) -> Data {
        guard width > 0, height > 0 else { return Data() }
        var raw: [UInt8] = []
        raw.reserveCapacity(height * (width * 3 + 1))
        for y in 0..<height {
            raw.append(0)
            for x in 0..<width {
                let (red, green, blue) = pixel(x, y)
                raw.append(red)
                raw.append(green)
                raw.append(blue)
            }
        }

        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        var ihdr = bigEndian(UInt32(width)) + bigEndian(UInt32(height))
        ihdr.append(contentsOf: [8, 2, 0, 0, 0])
        bytes.append(contentsOf: chunk(type: [73, 72, 68, 82], payload: ihdr))
        bytes.append(contentsOf: chunk(type: [73, 68, 65, 84], payload: zlibStore(raw)))
        bytes.append(contentsOf: chunk(type: [73, 69, 78, 68], payload: []))
        return Data(bytes)
    }

    /// Stored blocks are capped at 65535 bytes by the deflate format.
    private static func zlibStore(_ raw: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var offset = 0
        repeat {
            let length = min(raw.count - offset, 65_535)
            let last = offset + length == raw.count
            out.append(last ? 0x01 : 0x00)
            let len = UInt16(length)
            out.append(UInt8(len & 0xFF))
            out.append(UInt8((len >> 8) & 0xFF))
            let nlen = ~len
            out.append(UInt8(nlen & 0xFF))
            out.append(UInt8((nlen >> 8) & 0xFF))
            if length > 0 {
                out.append(contentsOf: raw[offset..<(offset + length)])
            }
            offset += length
        } while offset < raw.count
        let checksum = adler32(raw)
        out.append(UInt8((checksum >> 24) & 0xFF))
        out.append(UInt8((checksum >> 16) & 0xFF))
        out.append(UInt8((checksum >> 8) & 0xFF))
        out.append(UInt8(checksum & 0xFF))
        return out
    }

    private static func chunk(type: [UInt8], payload: [UInt8]) -> [UInt8] {
        var body = type
        body.append(contentsOf: payload)
        return bigEndian(UInt32(payload.count)) + body + bigEndian(crc32(body))
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask: UInt32 = (crc & 1) == 1 ? 0xEDB8_8320 : 0
                crc = (crc >> 1) ^ mask
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a = 1
        var b = 0
        for byte in bytes {
            a = (a + Int(byte)) % 65521
            b = (b + a) % 65521
        }
        return (UInt32(b) << 16) | UInt32(a)
    }
}
