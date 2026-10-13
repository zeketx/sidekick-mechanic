import Foundation

/// Compact garage summary on `POST /chat`. Matches `backend/chat_models.py`.
///
/// Photos stay on the phone. Done to-dos are left out. Long notes are cut so
/// the prompt stays bounded.
public struct GarageChatContext: Equatable, Sendable, Encodable {
    public var facts: [Fact]
    public var notes: [Note]
    public var openTodos: [Todo]

    public static let maxFacts = 24
    public static let maxNotes = 16
    public static let maxTodos = 16
    public static let maxFieldCharacters = 180

    public struct Fact: Equatable, Sendable, Encodable {
        public var label: String
        public var value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public struct Note: Equatable, Sendable, Encodable {
        public var name: String
        public var note: String

        public init(name: String, note: String) {
            self.name = name
            self.note = note
        }
    }

    public struct Todo: Equatable, Sendable, Encodable {
        public var title: String

        public init(title: String) {
            self.title = title
        }
    }

    public init(facts: [Fact] = [], notes: [Note] = [], openTodos: [Todo] = []) {
        self.facts = facts
        self.notes = notes
        self.openTodos = openTodos
    }

    public var isEmpty: Bool {
        facts.isEmpty && notes.isEmpty && openTodos.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case facts
        case notes
        case openTodos = "open_todos"
    }

    /// Builds the request payload, or `nil` when there is nothing to send.
    public static func compact(from library: GarageLibrary) -> GarageChatContext? {
        let facts = library.facts.compactMap { fact -> Fact? in
            let label = trimField(fact.label)
            let value = trimField(fact.value)
            guard !label.isEmpty, !value.isEmpty else { return nil }
            return Fact(label: label, value: value)
        }
        .prefix(maxFacts)

        let notes = library.items.compactMap { item -> Note? in
            let name = trimField(item.name)
            guard !name.isEmpty else { return nil }
            return Note(name: name, note: trimField(item.note))
        }
        .prefix(maxNotes)

        let todos = library.todos.compactMap { todo -> Todo? in
            guard !todo.isDone else { return nil }
            let title = trimField(todo.title)
            guard !title.isEmpty else { return nil }
            return Todo(title: title)
        }
        .prefix(maxTodos)

        let context = GarageChatContext(
            facts: Array(facts),
            notes: Array(notes),
            openTodos: Array(todos)
        )
        return context.isEmpty ? nil : context
    }

    public static func loadLive() -> GarageChatContext? {
        let library: GarageLibrary
        do {
            library = try GarageLibraryStore.live().load()
        } catch {
            library = .seeded()
        }
        return compact(from: library)
    }

    static func trimField(_ text: String) -> String {
        let cleaned = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if cleaned.count <= maxFieldCharacters {
            return cleaned
        }
        if maxFieldCharacters <= 1 {
            return String(cleaned.prefix(maxFieldCharacters))
        }
        return String(cleaned.prefix(maxFieldCharacters - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
