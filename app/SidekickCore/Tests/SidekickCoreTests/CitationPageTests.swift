import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SidekickCore

final class ManualPageSourceTests: XCTestCase {
    private var caches: [URL] = []

    override func tearDown() {
        for cache in caches {
            try? FileManager.default.removeItem(at: cache)
        }
        caches = []
        super.tearDown()
    }

    func testPlaceholderPNGRoundTripsAndIsObviouslyFake() throws {
        XCTAssertEqual(PNGChecksum.crc32(Array("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(PNGChecksum.adler32(Array("a".utf8)), 0x00620062)
        XCTAssertEqual(PNGChecksum.adler32([]), 1)

        let data = ManualPagePlaceholder.pngData()
        XCTAssertEqual(data, ManualPagePlaceholder.pngData())
        XCTAssertTrue(ManualPageImage.isPNG(data))
        let decoded = try decodeStoredPNG(data)
        XCTAssertEqual(decoded.width, ManualPagePlaceholder.width)
        XCTAssertEqual(decoded.height, ManualPagePlaceholder.height)
        XCTAssertEqual(pixel(decoded, x: 0, y: 0), RGB(0x2C, 0x2C, 0x2C))
        XCTAssertEqual(pixel(decoded, x: 3, y: 3), RGB(0xF2, 0xF2, 0xF2))
        XCTAssertEqual(pixel(decoded, x: 3, y: 8), RGB(0xD8, 0xD8, 0xD8))
    }

    func testStoredPNGRoundTripsAcrossDeflateBlockBoundary() throws {
        let width = 200
        let height = 120
        let data = StoredPNG.encode(width: width, height: height) { x, y in
            (UInt8(x & 0xFF), UInt8(y & 0xFF), 0x10)
        }
        let decoded = try decodeStoredPNG(data)
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        XCTAssertEqual(pixel(decoded, x: 0, y: 0), RGB(0, 0, 0x10))
        XCTAssertEqual(pixel(decoded, x: 199, y: 119), RGB(UInt8(199 & 0xFF), UInt8(119 & 0xFF), 0x10))
    }

    func testPageErrorMessagesAreSpecific() {
        XCTAssertEqual(
            ManualPageError.notConfigured.message,
            "The backend URL is not configured for this build."
        )
        XCTAssertEqual(ManualPageError.missingPage.message, "This manual page is not available.")
        XCTAssertEqual(
            ManualPageError.unavailable.message,
            "Could not load the manual page. Check the connection and try again."
        )
        XCTAssertEqual(ManualPageError.badImage.message, "The manual page image was unreadable.")
    }

    func testConfigurationComesFromTheEnvironmentOrPlist() throws {
        XCTAssertThrowsError(
            try ManualPageConfiguration.load(environment: [:], infoDictionary: nil)
        ) { error in
            XCTAssertEqual(error as? ManualPageError, .notConfigured)
        }

        let cache = try makeCache()
        let fromEnv = try ManualPageConfiguration.load(
            environment: [
                "SIDEKICK_BACKEND_URL": "http://127.0.0.1:8000",
                "SIDEKICK_BACKEND_TIMEOUT": "9",
                "SIDEKICK_PAGE_CACHE_DIR": cache.path,
            ],
            infoDictionary: ["SidekickBackendURL": "http://ignored.test"]
        )
        XCTAssertEqual(fromEnv.baseURL, URL(string: "http://127.0.0.1:8000"))
        XCTAssertEqual(fromEnv.requestTimeout, 9)
        XCTAssertEqual(fromEnv.cacheDirectory.standardizedFileURL, cache.standardizedFileURL)

        let fallback = try makeCache()
        let fromPlist = try ManualPageConfiguration.load(
            environment: ["SIDEKICK_PAGE_CACHE_DIR": ""],
            infoDictionary: ["SidekickBackendURL": "http://example.test:9"],
            defaultCacheDirectory: fallback
        )
        XCTAssertEqual(fromPlist.baseURL, URL(string: "http://example.test:9"))
        XCTAssertEqual(fromPlist.cacheDirectory, fallback)
        XCTAssertEqual(
            ManualPageConfiguration.platformCacheDirectory().lastPathComponent,
            "sidekick-manual-pages"
        )
    }

    func testMissingBackendURLFailsForRealDocumentsWithoutANetworkCall() async {
        let source = ManualPageSources.makeFromEnvironment(environment: [:], infoDictionary: nil)
        do {
            _ = try await source.pageImage(
                docID: DocumentID(rawValue: "2jz-ge-rm")!,
                page: fakePage()
            )
            XCTFail("expected not configured")
        } catch let error as ManualPageError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testFakeDocumentsLoadWithoutABackend() async throws {
        let source = ManualPageSources.makeFromEnvironment(environment: [:], infoDictionary: nil)
        let image = try await source.pageImage(docID: fakeDocument(), page: fakePage())
        XCTAssertEqual(image.pngData, ManualPagePlaceholder.pngData())
        XCTAssertEqual(image.docID, fakeDocument())
        XCTAssertEqual(image.page, fakePage())
    }

    func testConfiguredEnvironmentUsesTheCompositeSource() throws {
        let cache = try makeCache()
        let source = ManualPageSources.makeFromEnvironment(
            environment: [
                "SIDEKICK_BACKEND_URL": "http://example.test:9",
                "SIDEKICK_PAGE_CACHE_DIR": cache.path,
            ],
            infoDictionary: nil
        )
        XCTAssertTrue(source is CompositeManualPageSource)
    }

    func testCacheHitSkipsTheBackend() async throws {
        let cache = try makeCache()
        let png = ManualPagePlaceholder.pngData()
        let file = cacheFile(cache)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: file)
        let http = FakeHTTP(result: .failure(URLError(.notConnectedToInternet)))
        let source = CachingManualPageSource(configuration: configuration(cache), http: http)

        let image = try await source.pageImage(docID: fakeDocument(), page: fakePage())

        XCTAssertEqual(image.pngData, png)
        XCTAssertEqual(image.docID, fakeDocument())
        XCTAssertEqual(image.page, fakePage())
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testCacheMissFetchesAndStoresThePNG() async throws {
        let cache = try makeCache()
        let png = ManualPagePlaceholder.pngData()
        let http = FakeHTTP(result: .success((png, httpResponse(200))))
        let source = CachingManualPageSource(configuration: configuration(cache), http: http)

        let image = try await source.pageImage(docID: fakeDocument(), page: fakePage())
        XCTAssertEqual(image.pngData, png)
        XCTAssertEqual(try Data(contentsOf: cacheFile(cache)), png)
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(http.requests[0].httpMethod, "GET")
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "Accept"), "image/png")
        XCTAssertEqual(
            http.requests[0].url,
            URL(string: "http://example.test:9/manuals/FAKE-DOC/pages/999.png")
        )

        http.result = .failure(URLError(.notConnectedToInternet))
        let cached = try await source.pageImage(docID: fakeDocument(), page: fakePage())
        XCTAssertEqual(cached.pngData, png)
        XCTAssertEqual(http.requests.count, 1)
    }

    func testMissingAndBadResponsesAreNotCached() async throws {
        let cache = try makeCache()
        let http = FakeHTTP(result: .success((Data("missing".utf8), httpResponse(404))))
        let source = CachingManualPageSource(configuration: configuration(cache), http: http)

        await assertPageError(source, .missingPage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile(cache).path))

        http.result = .success((Data("FAKE-BYTES".utf8), httpResponse(200)))
        await assertPageError(source, .badImage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile(cache).path))

        http.result = .success((ManualPagePlaceholder.pngData(), httpResponse(500)))
        await assertPageError(source, .unavailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile(cache).path))

        http.result = .failure(URLError(.timedOut))
        await assertPageError(source, .unavailable)
    }

    func testCorruptCacheIsDroppedAndReplacedByTheBackendPNG() async throws {
        let cache = try makeCache()
        let file = cacheFile(cache)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-a-png".utf8).write(to: file)
        let png = ManualPagePlaceholder.pngData()
        let http = FakeHTTP(result: .success((png, httpResponse(200))))
        let source = CachingManualPageSource(configuration: configuration(cache), http: http)

        let image = try await source.pageImage(docID: fakeDocument(), page: fakePage())

        XCTAssertEqual(image.pngData, png)
        XCTAssertEqual(try Data(contentsOf: file), png)
        XCTAssertEqual(http.requests.count, 1)
    }

    func testUnsafeDocumentIDsDoNotEscapeTheCacheOrHitTheNetwork() async throws {
        let root = try makeCache()
        let cache = root.appendingPathComponent("pages", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let http = FakeHTTP(result: .success((ManualPagePlaceholder.pngData(), httpResponse(200))))
        let source = CachingManualPageSource(configuration: configuration(cache), http: http)
        let escaped = root.appendingPathComponent("999.png")

        for raw in ["..", "FAKE/DOC", "FAKE\\DOC"] {
            let docID = try XCTUnwrap(DocumentID(rawValue: raw))
            await assertPageError(source, .missingPage, docID: docID)
        }

        XCTAssertTrue(http.requests.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path), [])
    }

    func testGoDeeperFetchHitsTheBackendJSON() async throws {
        let cache = try makeCache()
        let payload = Data(
            """
            {"how_it_works":"From this page: FAKE-CHUNK.","what_to_test":"Look at the cover."}
            """.utf8
        )
        let http = FakeHTTP(
            result: .success(
                (
                    payload,
                    HTTPURLResponse(
                        url: URL(string: "http://example.test:9/manuals/2jz-ge-rm/pages/12/go-deeper")!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            )
        )
        let source = CachingGoDeeperSource(configuration: configuration(cache), http: http)
        let doc = try XCTUnwrap(DocumentID(rawValue: "2jz-ge-rm"))
        let page = try XCTUnwrap(PageNumber(rawValue: 12))

        let block = try await source.goDeeper(docID: doc, page: page, snippet: "")

        XCTAssertEqual(block.howItWorks, "From this page: FAKE-CHUNK.")
        XCTAssertEqual(block.whatToTest, "Look at the cover.")
        XCTAssertNil(block.tools)
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(
            http.requests[0].url,
            URL(string: "http://example.test:9/manuals/2jz-ge-rm/pages/12/go-deeper")
        )
    }

    func testCannedGoDeeperDoesNotHitTheNetwork() async throws {
        let http = FakeHTTP(result: .failure(URLError(.notConnectedToInternet)))
        let source = CompositeGoDeeperSource(
            remote: CachingGoDeeperSource(configuration: configuration(try makeCache()), http: http)
        )
        let doc = try XCTUnwrap(DocumentID(rawValue: "FAKE-DOC-2JZ"))
        let block = try await source.goDeeper(docID: doc, page: fakePage(), snippet: "")
        XCTAssertEqual(block, CannedGoDeeper.fuseBox)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testGoDeeperJSONIgnoresExtraKeysAndEmptySections() throws {
        let data = Data(
            """
            {"doc_id":"2jz-ge-rm","page":12,"how_it_works":"From this page: FAKE-CHUNK.","what_to_test":"","tools":"A flashlight."}
            """.utf8
        )
        let block = try JSONDecoder().decode(GoDeeper.self, from: data)
        XCTAssertEqual(block.howItWorks, "From this page: FAKE-CHUNK.")
        XCTAssertNil(block.whatToTest)
        XCTAssertNil(block.howToTest)
        XCTAssertEqual(block.tools, "A flashlight.")
        XCTAssertEqual(block.sections.map(\.title), ["How this works", "Tools"])
    }

    func testPageExcerptStripsControlCharactersAndCapsAroundSnippet() {
        let raw = "Torque:\u{0001} 18 N·m\n\tmore\u{007F}"
        XCTAssertEqual(PageExcerpt.stripControlCharacters(raw), "Torque: 18 N·m\n\tmore")

        let snippet = "Torque: 18 N·m is the spec"
        let page = "B02630\u{0001} " + String(repeating: "junk ", count: 40) + ". " + snippet + " " + String(repeating: "extra ", count: 80)
        let excerpt = PageExcerpt.aroundSnippet(pageText: page, snippet: snippet, limit: 80)
        XCTAssertEqual(excerpt?.contains("Torque: 18 N·m"), true)
        XCTAssertEqual(excerpt?.contains("\u{0001}"), false)
        XCTAssertEqual(excerpt?.contains("B02630"), false)
        XCTAssertLessThanOrEqual(excerpt?.count ?? 0, 81)
        XCTAssertEqual(excerpt?.hasSuffix("…"), true)

        XCTAssertNil(PageExcerpt.aroundSnippet(pageText: "inspect the cover.", snippet: "spark plug torque"))
        XCTAssertNil(PageExcerpt.aroundSnippet(pageText: "inspect the cover.", snippet: "  "))
    }

    func testGoDeeperStripsControlCharactersFromJSON() throws {
        let data = Data("{\"how_it_works\":\"Torque:\\u0001 18 N·m\"}".utf8)
        let block = try JSONDecoder().decode(GoDeeper.self, from: data)
        XCTAssertEqual(block.howItWorks, "Torque: 18 N·m")
    }

    func testCancelledFetchIsNotAPageFailure() async throws {
        let http = FakeHTTP(result: .failure(URLError(.cancelled)))
        let source = CachingManualPageSource(configuration: configuration(try makeCache()), http: http)
        do {
            _ = try await source.pageImage(docID: fakeDocument(), page: fakePage())
            XCTFail("expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    private func assertPageError(
        _ source: CachingManualPageSource,
        _ expected: ManualPageError,
        docID: DocumentID? = nil
    ) async {
        do {
            _ = try await source.pageImage(docID: docID ?? fakeDocument(), page: fakePage())
            XCTFail("expected \(expected)")
        } catch let error as ManualPageError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    private func configuration(_ cache: URL) -> ManualPageConfiguration {
        ManualPageConfiguration(
            baseURL: URL(string: "http://example.test:9")!,
            cacheDirectory: cache,
            requestTimeout: 5
        )
    }

    private func cacheFile(_ cache: URL) -> URL {
        cache.appendingPathComponent("FAKE-DOC").appendingPathComponent("999.png")
    }

    private func makeCache() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidekick-pages-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        caches.append(url)
        return url
    }

    private func httpResponse(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "http://example.test:9/manuals/FAKE-DOC/pages/999.png")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        )!
    }
}

private func fakeDocument() -> DocumentID {
    DocumentID(rawValue: "FAKE-DOC")!
}

private func fakePage() -> PageNumber {
    PageNumber(rawValue: 999)!
}

private struct RGB: Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

private struct DecodedPage {
    var width: Int
    var height: Int
    var rgb: [UInt8]
}

private enum PNGDecodeError: Error {
    case invalid
}

private enum PNGChecksum {
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
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

    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a = 1
        var b = 0
        for byte in bytes {
            a = (a + Int(byte)) % 65521
            b = (b + a) % 65521
        }
        return (UInt32(b) << 16) | UInt32(a)
    }
}

private func decodeStoredPNG(_ data: Data) throws -> DecodedPage {
    let bytes = [UInt8](data)
    guard bytes.count >= 8, Array(bytes.prefix(8)) == ManualPageImage.pngSignature else {
        throw PNGDecodeError.invalid
    }
    var index = 8
    var width = 0
    var height = 0
    var idat: [UInt8] = []
    var sawIHDR = false
    var sawIEND = false
    while index + 12 <= bytes.count, !sawIEND {
        let length = Int(readU32(bytes, index))
        index += 4
        let type = Array(bytes[index..<(index + 4)])
        index += 4
        guard index + length + 4 <= bytes.count else { throw PNGDecodeError.invalid }
        let payload = Array(bytes[index..<(index + length)])
        index += length
        let crc = readU32(bytes, index)
        index += 4
        guard PNGChecksum.crc32(type + payload) == crc else { throw PNGDecodeError.invalid }
        if type == Array("IHDR".utf8) {
            guard length == 13 else { throw PNGDecodeError.invalid }
            width = Int(readU32(payload, 0))
            height = Int(readU32(payload, 4))
            guard payload[8] == 8, payload[9] == 2, payload[10] == 0, payload[11] == 0,
                  payload[12] == 0
            else { throw PNGDecodeError.invalid }
            sawIHDR = true
        } else if type == Array("IDAT".utf8) {
            idat.append(contentsOf: payload)
        } else if type == Array("IEND".utf8) {
            sawIEND = true
        }
    }
    guard sawIHDR, sawIEND, width > 0, height > 0 else { throw PNGDecodeError.invalid }
    let raw = try inflateStored(idat)
    let rowBytes = width * 3 + 1
    guard raw.count == rowBytes * height else { throw PNGDecodeError.invalid }
    var rgb: [UInt8] = []
    rgb.reserveCapacity(width * height * 3)
    for row in 0..<height {
        let start = row * rowBytes
        guard raw[start] == 0 else { throw PNGDecodeError.invalid }
        rgb.append(contentsOf: raw[(start + 1)..<(start + rowBytes)])
    }
    return DecodedPage(width: width, height: height, rgb: rgb)
}

private func inflateStored(_ zlib: [UInt8]) throws -> [UInt8] {
    guard zlib.count >= 6, zlib[0] == 0x78, zlib[1] == 0x01 else { throw PNGDecodeError.invalid }
    var index = 2
    var raw: [UInt8] = []
    var finished = false
    while !finished {
        guard index < zlib.count else { throw PNGDecodeError.invalid }
        let header = zlib[index]
        index += 1
        guard (header >> 1) & 0x03 == 0 else { throw PNGDecodeError.invalid }
        guard index + 4 <= zlib.count else { throw PNGDecodeError.invalid }
        let length = Int(zlib[index]) | (Int(zlib[index + 1]) << 8)
        let complement = Int(zlib[index + 2]) | (Int(zlib[index + 3]) << 8)
        index += 4
        guard complement == (length ^ 0xFFFF) else { throw PNGDecodeError.invalid }
        guard index + length <= zlib.count else { throw PNGDecodeError.invalid }
        raw.append(contentsOf: zlib[index..<(index + length)])
        index += length
        finished = (header & 0x01) == 1
    }
    guard index + 4 == zlib.count else { throw PNGDecodeError.invalid }
    guard PNGChecksum.adler32(raw) == readU32(zlib, index) else { throw PNGDecodeError.invalid }
    return raw
}

private func readU32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
    (UInt32(bytes[index]) << 24)
        | (UInt32(bytes[index + 1]) << 16)
        | (UInt32(bytes[index + 2]) << 8)
        | UInt32(bytes[index + 3])
}

private func pixel(_ page: DecodedPage, x: Int, y: Int) -> RGB {
    let index = (y * page.width + x) * 3
    return RGB(page.rgb[index], page.rgb[index + 1], page.rgb[index + 2])
}
