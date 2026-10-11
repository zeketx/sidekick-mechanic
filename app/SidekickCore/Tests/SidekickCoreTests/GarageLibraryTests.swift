import Foundation
import XCTest
@testable import SidekickCore

@MainActor
final class GarageLibraryTests: XCTestCase {
    func testEditsPersistAcrossANewStore() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("garage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GarageLibraryStore(root: root)
        let ids = IDSource(["fact-1", "todo-1", "photo-1", "item-1"])
        let model = GarageModel(store: store, makeID: { ids.next() })

        XCTAssertEqual(
            model.library.facts.map(\.id),
            ["chassis", "engine", "donor-ecu", "obd-type", "harness", "photo-angles"]
        )
        XCTAssertEqual(
            model.library.facts.map(\.label),
            GarageFacts.confirmed.map(\.label) + GarageFacts.pending.map(\.label)
        )
        XCTAssertEqual(
            model.library.facts.map(\.value),
            GarageFacts.confirmed.map(\.value) + GarageFacts.pending.map(\.value)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.jsonURL.path))

        XCTAssertTrue(model.addFact(label: " Transmission ", value: " FAKE-NOTE "))
        XCTAssertTrue(model.addTodo(title: " FAKE-TODO "))
        XCTAssertTrue(model.addPhoto(caption: " bay ", jpeg: Data([1, 2, 3, 4])))
        XCTAssertTrue(model.addItem(name: " FAKE-PART ", note: " found it ", jpeg: Data([5, 6])))
        XCTAssertTrue(model.updateFact(id: "obd-type", label: "OBD type", value: "FAKE-OBD"))
        XCTAssertTrue(model.setTodoDone(id: "todo-1", isDone: true))

        let reloaded = try GarageLibraryStore(root: root).load()
        XCTAssertEqual(reloaded.facts.first { $0.id == "fact-1" }?.label, "Transmission")
        XCTAssertEqual(reloaded.facts.first { $0.id == "fact-1" }?.value, "FAKE-NOTE")
        XCTAssertEqual(reloaded.facts.first { $0.id == "fact-1" }?.isConfirmed, true)
        XCTAssertEqual(reloaded.facts.first { $0.id == "obd-type" }?.value, "FAKE-OBD")
        XCTAssertEqual(reloaded.facts.first { $0.id == "obd-type" }?.isConfirmed, true)
        XCTAssertEqual(reloaded.todos, [GarageTodo(id: "todo-1", title: "FAKE-TODO", isDone: true)])
        XCTAssertEqual(reloaded.photos, [GaragePhoto(id: "photo-1", caption: "bay", fileName: "photo-1.jpg")])
        XCTAssertEqual(try store.readPhoto(fileName: "photo-1.jpg"), Data([1, 2, 3, 4]))
        XCTAssertEqual(
            reloaded.items,
            [GarageItem(id: "item-1", name: "FAKE-PART", note: "found it", photoFileName: "item-1.jpg")]
        )
        XCTAssertEqual(try store.readPhoto(fileName: "item-1.jpg"), Data([5, 6]))

        let again = GarageModel(store: GarageLibraryStore(root: root), makeID: { "unused" })
        XCTAssertEqual(again.library, reloaded)
        XCTAssertTrue(again.removeFact(id: "fact-1"))
        XCTAssertTrue(again.removeTodo(id: "todo-1"))
        XCTAssertTrue(again.removePhoto(id: "photo-1"))
        XCTAssertTrue(again.removeItem(id: "item-1"))

        let after = try GarageLibraryStore(root: root).load()
        XCTAssertNil(after.facts.first { $0.id == "fact-1" })
        XCTAssertEqual(after.facts.count, 6)
        XCTAssertTrue(after.todos.isEmpty)
        XCTAssertTrue(after.photos.isEmpty)
        XCTAssertTrue(after.items.isEmpty)
        XCTAssertFalse(store.photoFileExists("photo-1.jpg"))
        XCTAssertFalse(store.photoFileExists("item-1.jpg"))
    }

    func testBlankFactTodoAndPhotoAreRejected() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("garage-blank-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GarageLibraryStore(root: root)
        let model = GarageModel(store: store, makeID: { "should-not-stick" })

        XCTAssertFalse(model.addFact(label: "  ", value: "FAKE"))
        XCTAssertFalse(model.addFact(label: "Name", value: " "))
        XCTAssertFalse(model.addTodo(title: " \n"))
        XCTAssertFalse(model.addItem(name: " ", note: "x", jpeg: nil))
        XCTAssertFalse(model.addPhoto(caption: "x", jpeg: Data()))
        XCTAssertFalse(model.updateFact(id: "missing", label: "Engine", value: "FAKE"))
        XCTAssertFalse(model.removeFact(id: "missing"))

        XCTAssertEqual(model.library.facts.count, 6)
        XCTAssertTrue(model.library.todos.isEmpty)
        XCTAssertTrue(model.library.photos.isEmpty)
        XCTAssertTrue(model.library.items.isEmpty)
        XCTAssertEqual(model.statusMessage, GarageCopy.photoFailed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.jsonURL.path))
    }

    func testSettingAFactBackToTBDClearsConfirmed() {
        let store = GarageLibraryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("unused"))
        let model = GarageModel(store: store, writes: false, makeID: { "unused" })
        XCTAssertTrue(model.updateFact(id: "engine", label: "Engine", value: "tbd"))
        XCTAssertEqual(model.library.facts.first { $0.id == "engine" }?.value, "tbd")
        XCTAssertEqual(model.library.facts.first { $0.id == "engine" }?.isConfirmed, false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.jsonURL.path))
    }

    func testCorruptFileIsSetAsideAndTheOriginalBytesSurvive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("garage-corrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("garage.json")
        try Data("not-json".utf8).write(to: url)
        let photo = root.appendingPathComponent("photos/keep.jpg")
        try FileManager.default.createDirectory(at: photo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([9, 9, 9]).write(to: photo)

        let store = GarageLibraryStore(root: root)
        XCTAssertThrowsError(try store.save(.seeded())) { error in
            XCTAssertEqual(error as? GarageStoreError, .unreadable)
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "not-json")

        let model = GarageModel(store: store, makeID: { "kept-todo" })
        XCTAssertEqual(
            model.library.facts.map(\.id),
            ["chassis", "engine", "donor-ecu", "obd-type", "harness", "photo-angles"]
        )
        XCTAssertEqual(model.statusMessage, GarageCopy.readFailed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let aside = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("garage.unreadable-") }
        XCTAssertEqual(aside.count, 1)
        XCTAssertEqual(try String(contentsOf: aside[0], encoding: .utf8), "not-json")
        XCTAssertEqual(try Data(contentsOf: photo), Data([9, 9, 9]))

        XCTAssertTrue(model.addTodo(title: "FAKE-TODO"))
        XCTAssertEqual(try String(contentsOf: aside[0], encoding: .utf8), "not-json")
        XCTAssertEqual(try Data(contentsOf: photo), Data([9, 9, 9]))
        let saved = try store.load()
        XCTAssertEqual(saved.todos.map(\.title), ["FAKE-TODO"])
        XCTAssertEqual(saved.version, GarageLibrary.currentVersion)
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("not-json"))
    }

    func testMissingVersionAndOptionalListsStillDecode() throws {
        let seeded = GarageLibrary.seeded()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(seeded)) as! [String: Any]
        object.removeValue(forKey: "version")
        object.removeValue(forKey: "photos")
        object.removeValue(forKey: "items")
        object.removeValue(forKey: "todos")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(GarageLibrary.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.facts.map(\.id), seeded.facts.map(\.id))
        XCTAssertTrue(decoded.photos.isEmpty)
        XCTAssertTrue(decoded.items.isEmpty)
        XCTAssertTrue(decoded.todos.isEmpty)

        object["version"] = 99
        let newer = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(GarageLibrary.self, from: newer))
    }

    func testNamedDirectorySurvivesRelaunchAndIsNotApplicationSupport() throws {
        let name = "sidekick-garage-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("KEEP".utf8).write(to: root.appendingPathComponent("garage.json"))

        let environment = [GarageStoreLocation.directoryEnvironmentKey: name]
        let store = GarageLibraryStore.live(arguments: ["SidekickMechanic"], environment: environment)
        XCTAssertEqual(store.root.lastPathComponent, name)
        XCTAssertEqual(try String(contentsOf: store.jsonURL, encoding: .utf8), "KEEP")
        let again = GarageLibraryStore.live(arguments: ["SidekickMechanic"], environment: environment)
        XCTAssertEqual(again.root.standardizedFileURL.path, store.root.standardizedFileURL.path)
        XCTAssertEqual(try String(contentsOf: again.jsonURL, encoding: .utf8), "KEEP")
        if let support = try? GarageLibraryStore.defaultRoot() {
            XCTAssertNotEqual(store.root.standardizedFileURL.path, support.standardizedFileURL.path)
        }
        XCTAssertNil(GarageStoreLocation.directoryName(environment: [
            GarageStoreLocation.directoryEnvironmentKey: "../escape",
        ]))
        XCTAssertTrue(GarageStoreLocation.showsSamplePhoto(arguments: ["SidekickMechanic"], environment: environment))
    }

    func testGaragePreviewLaunchArgumentsDoNotEnableDemo() {
        XCTAssertEqual(
            GaragePreview.parse(arguments: ["SidekickMechanic", "-screen", "garage-edit"], environment: [:]),
            .edit
        )
        XCTAssertEqual(
            GaragePreview.parse(arguments: ["SidekickMechanic"], environment: ["SIDEKICK_SCREEN": "garage-todos"]),
            .todos
        )
        XCTAssertNil(
            GaragePreview.parse(arguments: ["SidekickMechanic", "-screen", "onboarding-1"], environment: [:])
        )
        let launch = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "garage-edit"],
            environment: [:]
        )
        XCTAssertFalse(launch.enablesDemoMode)
        XCTAssertNil(launch.screen)
        XCTAssertNil(launch.lookBackScreen)
        XCTAssertEqual(GaragePreview.todos.sampleLibrary().todos.map(\.title), ["Check the spare", "Wash the truck"])
        XCTAssertEqual(GaragePreview.view.sampleLibrary().todos, [])
    }

    func testGarageScrimDarkensAsTheSheetCoversMore() {
        XCTAssertEqual(GarageScrim.opacity(coverage: 0), 0.5)
        XCTAssertEqual(GarageScrim.opacity(coverage: 0.5), 0.625)
        XCTAssertEqual(GarageScrim.opacity(coverage: 1), 0.75)
        XCTAssertEqual(GarageScrim.opacity(coverage: -1), 0.5)
        XCTAssertEqual(GarageScrim.opacity(coverage: 2), 0.75)
    }

    func testTemporaryStoreKeepsNotesAcrossANewLiveStore() async throws {
        XCTAssertFalse(
            GarageStoreLocation.usesTemporaryStore(arguments: ["SidekickMechanic"], environment: [:])
        )
        XCTAssertTrue(
            GarageStoreLocation.usesTemporaryStore(
                arguments: ["SidekickMechanic", "-garageTemporaryStore", "1"],
                environment: [:]
            )
        )
        XCTAssertFalse(
            GarageStoreLocation.usesTemporaryStore(
                arguments: ["SidekickMechanic", "-garageTemporaryStore", "0"],
                environment: [:]
            )
        )
        XCTAssertTrue(
            GarageStoreLocation.usesTemporaryStore(
                arguments: ["SidekickMechanic"],
                environment: ["SIDEKICK_GARAGE_TEMPORARY": "yes"]
            )
        )

        let arguments = ["SidekickMechanic", "-garageTemporaryStore", "1"]
        let clean = try GarageStoreLocation.wipeTemporaryRoot()
        XCTAssertEqual(clean.lastPathComponent, GarageStoreLocation.temporaryFolderName)

        let model = GarageModel(
            store: .live(arguments: arguments, environment: [:]),
            makeID: { "fact-kept" }
        )
        XCTAssertTrue(model.addFact(label: "FAKE-LABEL", value: "FAKE-NOTE"))
        XCTAssertTrue(model.addTodo(title: "FAKE-TODO"))
        XCTAssertTrue(model.setTodoDone(id: "fact-kept", isDone: true))
        XCTAssertTrue(model.addPhoto(caption: "FAKE-PHOTO", jpeg: Data([9, 9])))
        XCTAssertTrue(model.addItem(name: "FAKE-PART", note: "FAKE-NOTE", jpeg: nil))

        let again = GarageLibraryStore.live(arguments: arguments, environment: [:])
        XCTAssertEqual(again.root.lastPathComponent, GarageStoreLocation.temporaryFolderName)
        XCTAssertNotEqual(again.root.path, try GarageLibraryStore.defaultRoot().path)
        let loaded = try again.load()
        XCTAssertEqual(loaded.facts.first { $0.id == "fact-kept" }?.value, "FAKE-NOTE")
        XCTAssertEqual(loaded.todos.map(\.title), ["FAKE-TODO"])
        XCTAssertEqual(loaded.todos.map(\.isDone), [true])
        XCTAssertEqual(loaded.photos.map(\.caption), ["FAKE-PHOTO"])
        XCTAssertEqual(try again.readPhoto(fileName: "fact-kept.jpg"), Data([9, 9]))
        XCTAssertEqual(loaded.items.map(\.name), ["FAKE-PART"])
        try? FileManager.default.removeItem(at: again.root)
    }

    func testRejectedFileNameCannotEscapeThePhotoFolder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("garage-path-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GarageLibraryStore(root: root)
        XCTAssertThrowsError(try store.writePhoto(Data([1]), fileName: "../escape.jpg")) { error in
            XCTAssertEqual(error as? GarageStoreError, .badFileName)
        }
        XCTAssertFalse(store.photoFileExists("../escape.jpg"))
    }
}

private final class IDSource: @unchecked Sendable {
    var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        values.removeFirst()
    }
}
