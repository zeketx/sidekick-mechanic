import XCTest
@testable import SidekickCore

final class DemoModeTests: XCTestCase {
    func testCatalogDecodesSnakeCaseKeys() throws {
        let json = Data(
            #"""
            {
              "demo": true,
              "label": "Demo data. Scripted highlights. Not Zeke's truck.",
              "attribution_url": "/demo/attribution",
              "default_photo_id": "commons-hilux-2jz",
              "photos": [
                {
                  "photo_id": "hrymx-2jz-ge-25308847029",
                  "short_name": "2JZ-GE prototype",
                  "image_url": "/demo/photos/hrymx-2jz-ge-25308847029/image",
                  "attribution": "FAKE-ATTRIBUTION by FAKE-AUTHOR",
                  "author": "FAKE-AUTHOR",
                  "license": "CC BY 2.0",
                  "license_url": "https://creativecommons.org/licenses/by/2.0/",
                  "source_page_url": "https://example.test/fake",
                  "engine_as_stated": "2JZ-GE",
                  "share_alike": false,
                  "width": 1600,
                  "height": 1067,
                  "parts": [
                    {
                      "part_id": "throttle-body",
                      "display_name": "throttle body",
                      "demo_state": "outline"
                    }
                  ]
                }
              ]
            }
            """#.utf8
        )
        let catalog = try JSONDecoder().decode(DemoCatalog.self, from: json)
        XCTAssertTrue(catalog.demo)
        XCTAssertEqual(catalog.defaultPhotoID, "commons-hilux-2jz")
        XCTAssertEqual(catalog.photos.count, 1)
        XCTAssertEqual(catalog.photos[0].photoID, "hrymx-2jz-ge-25308847029")
        XCTAssertEqual(catalog.photos[0].shortName, "2JZ-GE prototype")
        XCTAssertEqual(catalog.photos[0].thumbnailLabel, "2JZ-GE prototype")
        XCTAssertFalse(catalog.photos[0].shareAlike)
        XCTAssertEqual(catalog.photos[0].parts[0].demoState, "outline")
    }

    func testFeedbackBodyUsesSnakeCaseAndDemoActions() throws {
        let body = DemoFeedbackBody(
            photoID: "hrymx-2jz-ge-25308847029",
            partID: "intake-plenum",
            action: .notThis
        )
        let data = try JSONEncoder().encode(body)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )
        XCTAssertEqual(object["photo_id"], "hrymx-2jz-ge-25308847029")
        XCTAssertEqual(object["part_id"], "intake-plenum")
        XCTAssertEqual(object["action"], "not_this")
    }

    func testDemoImageURLUsesCatalogPath() {
        let config = ChatClientConfiguration(baseURL: URL(string: "http://127.0.0.1:8000")!)
        XCTAssertEqual(
            config.demoPhotosURL,
            URL(string: "http://127.0.0.1:8000/demo/photos")
        )
        XCTAssertEqual(
            config.demoImageURL(photoID: "hrymx-2jz-ge-25308847029"),
            URL(string: "http://127.0.0.1:8000/demo/photos/hrymx-2jz-ge-25308847029/image")
        )
    }

    func testLaunchArgumentsPreselectPhotoStyleAndQuestion() {
        let launch = DemoLaunchOptions.parse(
            arguments: [
                "SidekickMechanic",
                "-demoPhoto", "hilux",
                "-demoPart", "fuse-relay-box",
                "-demoState", "outline",
                "-demoStyle", "dim",
            ],
            environment: [:]
        )
        XCTAssertTrue(launch.enablesDemoMode)
        XCTAssertEqual(launch.resolvedPhotoID, "commons-hilux-2jz")
        XCTAssertEqual(launch.style, .dim)
        XCTAssertEqual(launch.cannedQuestion, "where's the fuse box?")
    }

    func testLaunchEnvironmentHooksMatchArguments() {
        let launch = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic"],
            environment: [
                "SIDEKICK_DEMO_PHOTO": "hrymx",
                "SIDEKICK_DEMO_STATE": "not_found",
                "SIDEKICK_DEMO_STYLE": "circle",
            ]
        )
        XCTAssertEqual(launch.resolvedPhotoID, "hrymx-2jz-ge-25308847029")
        XCTAssertEqual(launch.style, .circle)
        XCTAssertEqual(launch.cannedQuestion, "where are the coil packs?")
    }

    func testShortNamesCoverTheFourDemoPhotos() {
        XCTAssertEqual(DemoLaunchOptions.shortName(for: "commons-hilux-2jz"), "Hilux")
        XCTAssertEqual(DemoLaunchOptions.shortName(for: "commons-supra-n5abh"), "Supra (2JZ-GTE)")
        XCTAssertEqual(DemoLaunchOptions.shortName(for: "hrymx-2jz-ge-25308847029"), "2JZ-GE prototype")
        XCTAssertEqual(DemoLaunchOptions.shortName(for: "flickr-robmarson-6763892857"), "2JZ bay")
    }

    func testEmptyLaunchLeavesDemoOff() {
        let launch = DemoLaunchOptions.parse(arguments: ["SidekickMechanic"], environment: [:])
        XCTAssertFalse(launch.enablesDemoMode)
        XCTAssertFalse(launch.showDemoChrome)
    }
}
