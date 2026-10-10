import Foundation
import Observation

/// Plain-language copy for the editable garage. Onboarding keeps `GarageFacts.tbdNotice`.
public enum GarageCopy {
    public static let title = "Your garage"
    public static let notice = "Notes you keep about this truck. They stay on this phone."
    public static let tbdHint = "TBD means it is not known yet. Fill it in when you find out."
    public static let edit = "Edit"
    public static let finish = "Finish"
    public static let done = "Done"
    public static let about = "About this truck"
    public static let confirmed = "Confirmed"
    public static let pending = "Still TBD"
    public static let photos = "Photos"
    public static let photosEmpty = "No photos yet."
    public static let addPhoto = "Add a photo"
    public static let choosePhoto = "Choose from library"
    public static let takePhoto = "Take a photo"
    public static let captionLabel = "A short note (optional)"
    public static let captionPlaceholder = "Engine bay, driver's side"
    public static let parts = "Parts and papers"
    public static let partsEmpty = "Nothing saved here yet."
    public static let addPart = "Add a part or paper"
    public static let partName = "Name"
    public static let partNamePlaceholder = "Wiring harness"
    public static let partNote = "Note (optional)"
    public static let partNotePlaceholder = "Where you found it"
    public static let addPhotoOptional = "Add a photo (optional)"
    public static let todos = "To-do"
    public static let todosEmpty = "Nothing on the list yet."
    public static let todoPlaceholder = "Something to do on the truck"
    public static let add = "Add"
    public static let addTodo = "Add a to-do"
    /// Shown only for a test garage folder, so a UI test can save a photo without the library picker.
    public static let samplePhoto = "Use a sample photo"
    public static let addFact = "Add a fact"
    public static let change = "Change"
    public static let remove = "Remove"
    public static let save = "Save"
    public static let cancel = "Cancel"
    public static let factWhat = "What is it?"
    public static let factWhatPlaceholder = "Engine"
    public static let factValue = "What do you know?"
    public static let factValuePlaceholder = "2JZ-GE swap"
    public static let addFactTitle = "Add a fact"
    public static let editFactTitle = "Change this fact"
    public static let addPhotoTitle = "Add a photo"
    public static let addPartTitle = "Add a part or paper"
    public static let saveFailed = "Could not save these notes on this phone."
    public static let readFailed = "Saved notes could not be read. They are still on this phone. Showing the starting list."
    public static let photoFailed = "Could not save that photo."
    public static let photoUnreadable = "That photo could not be read. Try another one."
}

/// A photo the owner added. The JPEG lives beside the JSON file.
public struct GaragePhoto: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var caption: String
    public var fileName: String

    public init(id: String, caption: String, fileName: String) {
        self.id = id
        self.caption = caption
        self.fileName = fileName
    }
}

/// A part or a paper the owner wants to remember. The photo is optional.
public struct GarageItem: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var note: String
    public var photoFileName: String?

    public init(id: String, name: String, note: String, photoFileName: String? = nil) {
        self.id = id
        self.name = name
        self.note = note
        self.photoFileName = photoFileName
    }
}

/// One line on the truck's to-do list.
public struct GarageTodo: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var isDone: Bool

    public init(id: String, title: String, isDone: Bool) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

/// Facts, photos, parts, and to-dos kept on the phone.
public struct GarageLibrary: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var facts: [GarageFact]
    public var photos: [GaragePhoto]
    public var items: [GarageItem]
    public var todos: [GarageTodo]

    public init(
        facts: [GarageFact],
        photos: [GaragePhoto] = [],
        items: [GarageItem] = [],
        todos: [GarageTodo] = [],
        version: Int = currentVersion
    ) {
        self.version = version
        self.facts = facts
        self.photos = photos
        self.items = items
        self.todos = todos
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case facts
        case photos
        case items
        case todos
    }

    /// Missing `version` is 1. A newer version, or a file with no `facts` array, fails so the store can set it aside.
    /// Missing photo, part, and to-do arrays become empty, so a future optional list does not throw away the file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        guard version <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "garage version \(version) is newer than \(Self.currentVersion)"
            )
        }
        self.version = version
        facts = try container.decode([GarageFact].self, forKey: .facts)
        photos = try container.decodeIfPresent([GaragePhoto].self, forKey: .photos) ?? []
        items = try container.decodeIfPresent([GarageItem].self, forKey: .items) ?? []
        todos = try container.decodeIfPresent([GarageTodo].self, forKey: .todos) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(facts, forKey: .facts)
        try container.encode(photos, forKey: .photos)
        try container.encode(items, forKey: .items)
        try container.encode(todos, forKey: .todos)
    }

    /// First launch. Same rows as onboarding, so nothing disappears.
    public static func seeded() -> GarageLibrary {
        GarageLibrary(facts: GarageFacts.confirmed + GarageFacts.pending)
    }

    public static func isTBD(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("TBD") == .orderedSame
    }

    /// Exact "TBD" is still unknown. Editing a TBD row into any other value counts as known.
    public static func confirmation(wasConfirmed: Bool, oldValue: String, newValue: String) -> Bool {
        if isTBD(newValue) { return false }
        if isTBD(oldValue) { return true }
        return wasConfirmed
    }

    @discardableResult
    public mutating func addFact(id: String, label: String, value: String) -> GarageFact? {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, !value.isEmpty else { return nil }
        let fact = GarageFact(id: id, label: label, value: value, isConfirmed: !Self.isTBD(value))
        facts.append(fact)
        return fact
    }

    @discardableResult
    public mutating func updateFact(id: String, label: String, value: String) -> GarageFact? {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, !value.isEmpty else { return nil }
        guard let index = facts.firstIndex(where: { $0.id == id }) else { return nil }
        let existing = facts[index]
        facts[index].label = label
        facts[index].value = value
        facts[index].isConfirmed = Self.confirmation(
            wasConfirmed: existing.isConfirmed,
            oldValue: existing.value,
            newValue: value
        )
        return facts[index]
    }

    @discardableResult
    public mutating func removeFact(id: String) -> GarageFact? {
        guard let index = facts.firstIndex(where: { $0.id == id }) else { return nil }
        return facts.remove(at: index)
    }

    @discardableResult
    public mutating func addTodo(id: String, title: String) -> GarageTodo? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let todo = GarageTodo(id: id, title: title, isDone: false)
        todos.append(todo)
        return todo
    }

    @discardableResult
    public mutating func setTodoDone(id: String, isDone: Bool) -> GarageTodo? {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return nil }
        todos[index].isDone = isDone
        return todos[index]
    }

    @discardableResult
    public mutating func removeTodo(id: String) -> GarageTodo? {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return nil }
        return todos.remove(at: index)
    }

    @discardableResult
    public mutating func addItem(id: String, name: String, note: String, photoFileName: String?) -> GarageItem? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let item = GarageItem(id: id, name: name, note: note, photoFileName: photoFileName)
        items.append(item)
        return item
    }

    @discardableResult
    public mutating func removeItem(id: String) -> GarageItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }
}

public enum GarageStoreError: Error, Equatable {
    case unreadable
    case emptyPhoto
    case badFileName
}

/// Black dim behind a garage sheet. Higher coverage (sheet pulled up) is darker.
public enum GarageScrim {
    /// 0.5 when the sheet is at the bottom of its travel, 0.75 when it covers the screen.
    public static func opacity(coverage: Double) -> Double {
        let t = min(1, max(0, coverage))
        return 0.5 + 0.25 * t
    }
}

/// `-garageTemporaryStore 1` keeps UI-test edits out of Application Support.
/// `SIDEKICK_GARAGE_DIRECTORY` is a folder name under the app's temporary directory.
/// The app creates that folder and never deletes it. The test picks a new name per run.
/// Application Support is never wiped.
public enum GarageStoreLocation {
    public static let temporaryFlag = "-garageTemporaryStore"
    public static let temporaryEnvironmentKey = "SIDEKICK_GARAGE_TEMPORARY"
    public static let directoryEnvironmentKey = "SIDEKICK_GARAGE_DIRECTORY"
    public static let temporaryFolderName = "sidekick-garage-uitest"

    /// A single path component. Slashes and `..` are rejected so the name cannot leave the temp directory.
    public static func directoryName(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let raw = environment[directoryEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            raw != ".",
            raw != "..",
            !raw.contains("/"),
            !raw.contains("\\")
        else {
            return nil
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return raw
    }

    public static func showsSamplePhoto(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        directoryName(environment: environment) != nil
            || usesTemporaryStore(arguments: arguments, environment: environment)
    }

    public static func usesTemporaryStore(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if arguments.contains(temporaryFlag) {
            if let raw = LaunchArgument.flag(arguments, temporaryFlag) {
                return FeatureFlags.isEnabled(raw)
            }
            return true
        }
        return FeatureFlags.isEnabled(environment[temporaryEnvironmentKey])
    }

    public static func temporaryRoot(fileManager: FileManager = .default) throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(temporaryFolderName, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    public static func wipeTemporaryRoot(fileManager: FileManager = .default) throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(temporaryFolderName, isDirectory: true)
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

/// JSON file plus JPEG sidecars. The app uses Application Support. Tests pass a temp folder.
public struct GarageLibraryStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func live(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> GarageLibraryStore {
        if let name = GarageStoreLocation.directoryName(environment: environment) {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(name, isDirectory: true)
            if (try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)) != nil {
                return GarageLibraryStore(root: root)
            }
        }
        if GarageStoreLocation.usesTemporaryStore(arguments: arguments, environment: environment),
           let root = try? GarageStoreLocation.temporaryRoot() {
            return GarageLibraryStore(root: root)
        }
        if let root = try? defaultRoot() {
            return GarageLibraryStore(root: root)
        }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidekickMechanic/Garage", isDirectory: true)
        return GarageLibraryStore(root: fallback)
    }

    public static func defaultRoot() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("SidekickMechanic/Garage", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    var jsonURL: URL {
        root.appendingPathComponent("garage.json")
    }

    var photosURL: URL {
        root.appendingPathComponent("photos", isDirectory: true)
    }

    /// Missing file returns the seed and does not write.
    /// A file that does not decode is moved to `garage.unreadable-<timestamp>.json` before this throws.
    public func load() throws -> GarageLibrary {
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            return .seeded()
        }
        if let data = try? Data(contentsOf: jsonURL),
           let library = try? JSONDecoder().decode(GarageLibrary.self, from: data) {
            return library
        }
        try quarantineUnreadableFile()
        throw GarageStoreError.unreadable
    }

    public func save(_ library: GarageLibrary) throws {
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            let existing = try Data(contentsOf: jsonURL)
            guard (try? JSONDecoder().decode(GarageLibrary.self, from: existing)) != nil else {
                throw GarageStoreError.unreadable
            }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        try data.write(to: jsonURL, options: .atomic)
    }

    /// Moves `garage.json` aside. Does not touch `photos/`. A name that is already taken gets `-2`, `-3`, and so on.
    private func quarantineUnreadableFile() throws {
        let source = jsonURL
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        var suffix = ""
        var attempt = 1
        while attempt < 100 {
            let name = "garage.unreadable-\(stamp)\(suffix).json"
            let destination = root.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.moveItem(at: source, to: destination)
                return
            }
            attempt += 1
            suffix = "-\(attempt)"
        }
        throw GarageStoreError.unreadable
    }

    public func writePhoto(_ data: Data, fileName: String) throws {
        guard !data.isEmpty else { throw GarageStoreError.emptyPhoto }
        try validateFileName(fileName)
        try FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        try data.write(to: photosURL.appendingPathComponent(fileName), options: .atomic)
    }

    public func readPhoto(fileName: String) throws -> Data {
        try validateFileName(fileName)
        let url = photosURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else {
            throw GarageStoreError.unreadable
        }
        return data
    }

    public func removePhoto(fileName: String) throws {
        try validateFileName(fileName)
        let url = photosURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func photoFileExists(_ fileName: String) -> Bool {
        guard (try? validateFileName(fileName)) != nil else { return false }
        return FileManager.default.fileExists(atPath: photosURL.appendingPathComponent(fileName).path)
    }

    private func validateFileName(_ fileName: String) throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              fileName.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else {
            throw GarageStoreError.badFileName
        }
    }
}

/// Screenshot launch. `-screen garage|garage-edit|garage-add-photo|garage-add-part|garage-todos`.
public enum GaragePreview: String, Equatable, Sendable {
    case view = "garage"
    case edit = "garage-edit"
    case addPhoto = "garage-add-photo"
    case addPart = "garage-add-part"
    case todos = "garage-todos"

    public var startsEditing: Bool { self != .view }

    public static func parse(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> GaragePreview? {
        let raw = LaunchArgument.flag(arguments, "-screen") ?? environment["SIDEKICK_SCREEN"] ?? ""
        return GaragePreview(rawValue: raw)
    }

    /// In-memory sample so a screenshot of the list is not an empty section.
    /// This is not written to the owner's garage unless a preview store is used.
    public func sampleLibrary() -> GarageLibrary {
        var library = GarageLibrary.seeded()
        if self == .todos {
            library.todos = [
                GarageTodo(id: "preview-open", title: "Check the spare", isDone: false),
                GarageTodo(id: "preview-done", title: "Wash the truck", isDone: true),
            ]
        }
        return library
    }
}

/// Editable garage. Each successful change is written before the call returns.
@MainActor
@Observable
public final class GarageModel {
    public private(set) var library: GarageLibrary
    public var isEditing: Bool
    public private(set) var statusMessage: String?

    @ObservationIgnored private let store: GarageLibraryStore
    @ObservationIgnored private let makeID: @Sendable () -> String
    @ObservationIgnored private let writes: Bool

    public init(
        store: GarageLibraryStore,
        isEditing: Bool = false,
        library: GarageLibrary? = nil,
        writes: Bool = true,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.store = store
        self.isEditing = isEditing
        self.writes = writes
        self.makeID = makeID
        if let library {
            self.library = library
            self.statusMessage = nil
        } else {
            do {
                self.library = try store.load()
                self.statusMessage = nil
            } catch {
                self.library = .seeded()
                self.statusMessage = GarageCopy.readFailed
            }
        }
    }

    @discardableResult
    public func addFact(label: String, value: String) -> Bool {
        let id = makeID()
        return commit { library in
            library.addFact(id: id, label: label, value: value) != nil
        }
    }

    @discardableResult
    public func updateFact(id: String, label: String, value: String) -> Bool {
        commit { library in
            library.updateFact(id: id, label: label, value: value) != nil
        }
    }

    @discardableResult
    public func removeFact(id: String) -> Bool {
        commit { library in
            library.removeFact(id: id) != nil
        }
    }

    @discardableResult
    public func addTodo(title: String) -> Bool {
        let id = makeID()
        return commit { library in
            library.addTodo(id: id, title: title) != nil
        }
    }

    @discardableResult
    public func setTodoDone(id: String, isDone: Bool) -> Bool {
        commit { library in
            library.setTodoDone(id: id, isDone: isDone) != nil
        }
    }

    @discardableResult
    public func removeTodo(id: String) -> Bool {
        commit { library in
            library.removeTodo(id: id) != nil
        }
    }

    @discardableResult
    public func addPhoto(caption: String, jpeg: Data) -> Bool {
        guard !jpeg.isEmpty else {
            statusMessage = GarageCopy.photoFailed
            return false
        }
        let id = makeID()
        let fileName = "\(id).jpg"
        let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return attach(jpeg: jpeg, fileName: fileName) { library in
            library.photos.append(GaragePhoto(id: id, caption: caption, fileName: fileName))
        }
    }

    @discardableResult
    public func removePhoto(id: String) -> Bool {
        guard let photo = library.photos.first(where: { $0.id == id }) else { return false }
        let saved = commit { library in
            library.photos.removeAll { $0.id == id }
            return true
        }
        if saved {
            try? store.removePhoto(fileName: photo.fileName)
        }
        return saved
    }

    @discardableResult
    public func addItem(name: String, note: String, jpeg: Data?) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        let id = makeID()
        if let jpeg, !jpeg.isEmpty {
            let fileName = "\(id).jpg"
            return attach(jpeg: jpeg, fileName: fileName) { library in
                _ = library.addItem(id: id, name: name, note: note, photoFileName: fileName)
            }
        }
        return commit { library in
            library.addItem(id: id, name: name, note: note, photoFileName: nil) != nil
        }
    }

    @discardableResult
    public func removeItem(id: String) -> Bool {
        guard let item = library.items.first(where: { $0.id == id }) else { return false }
        let saved = commit { library in
            library.items.removeAll { $0.id == id }
            return true
        }
        if saved, let fileName = item.photoFileName {
            try? store.removePhoto(fileName: fileName)
        }
        return saved
    }

    public func imageData(fileName: String) -> Data? {
        try? store.readPhoto(fileName: fileName)
    }

    private func attach(jpeg: Data, fileName: String, mutate: (inout GarageLibrary) -> Void) -> Bool {
        do {
            try store.writePhoto(jpeg, fileName: fileName)
        } catch {
            statusMessage = GarageCopy.photoFailed
            return false
        }
        let saved = commit { library in
            mutate(&library)
            return true
        }
        if !saved {
            try? store.removePhoto(fileName: fileName)
        }
        return saved
    }

    private func commit(_ mutate: (inout GarageLibrary) -> Bool) -> Bool {
        var updated = library
        guard mutate(&updated) else { return false }
        let previous = library
        library = updated
        guard persist() else {
            library = previous
            return false
        }
        return true
    }

    private func persist() -> Bool {
        guard writes else { return true }
        do {
            try store.save(library)
            statusMessage = nil
            return true
        } catch {
            statusMessage = GarageCopy.saveFailed
            return false
        }
    }
}
