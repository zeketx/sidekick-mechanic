import PhotosUI
import SidekickCore
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import UIKit

/// Garage opened from Chat. Onboarding keeps the display-only list.
///
/// Edit and Done are plain text in this header. A toolbar item picks up an iOS 26 glass capsule.
struct GarageScreen: View {
    @State private var model: GarageModel
    @State private var sheet: GarageSheet?
    @State private var formDetent: PresentationDetent = .large
    @State private var todoDraft = ""
    var onClose: () -> Void

    init(onClose: @escaping () -> Void, preview: GaragePreview? = nil) {
        self.onClose = onClose
        if let preview {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("sidekick-garage-preview", isDirectory: true)
                .appendingPathComponent(preview.rawValue, isDirectory: true)
            _model = State(
                initialValue: GarageModel(
                    store: GarageLibraryStore(root: root),
                    isEditing: preview.startsEditing,
                    library: preview.sampleLibrary()
                )
            )
            _sheet = State(initialValue: preview.openingSheet)
        } else {
            _model = State(initialValue: GarageModel(store: .live()))
            _sheet = State(initialValue: nil)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(GarageCopy.notice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("onboarding.garage")
                    Text(GarageCopy.tbdHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let statusMessage = model.statusMessage {
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("garage.status")
                    }

                    factsSection
                    photosSection
                    itemsSection
                    todosSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JobSheetChrome.screen)
        .sheet(item: $sheet) { item in
            GarageEditorSheet(sheet: item, model: model, onClose: { sheet = nil })
                .presentationDetents([.medium, .large], selection: $formDetent)
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.white)
                .presentationCornerRadius(CGFloat(JobSheetLayout.topCornerRadius))
                .preferredColorScheme(.light)
        }
    }

    private var header: some View {
        ZStack {
            Text(GarageCopy.title)
                .font(.headline)
                .accessibilityIdentifier("garage.title")
            HStack {
                Button(model.isEditing ? GarageCopy.finish : GarageCopy.edit) {
                    model.isEditing.toggle()
                }
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(.primary)
                .accessibilityIdentifier(model.isEditing ? "garage.finish" : "garage.edit")
                Spacer()
                Button(GarageCopy.done, action: onClose)
                    .buttonStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("garage.done")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(GarageCopy.about)
            if model.isEditing {
                addButton(GarageCopy.addFact, identifier: "garage.addFact") {
                    present(.addFact)
                }
            }
            if !confirmedFacts.isEmpty {
                sectionTitle(GarageCopy.confirmed)
                ForEach(confirmedFacts) { fact in
                    factCard(fact)
                }
            }
            if !pendingFacts.isEmpty {
                sectionTitle(GarageCopy.pending)
                    .padding(.top, 4)
                ForEach(pendingFacts) { fact in
                    factCard(fact)
                }
            }
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(GarageCopy.photos)
                .padding(.top, 8)
            if model.isEditing {
                addButton(GarageCopy.addPhoto, identifier: "garage.addPhoto") {
                    present(.addPhoto)
                }
            }
            if model.library.photos.isEmpty {
                Text(GarageCopy.photosEmpty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(model.library.photos) { photo in
                        photoCard(photo)
                    }
                }
            }
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(GarageCopy.parts)
                .padding(.top, 8)
            if model.isEditing {
                addButton(GarageCopy.addPart, identifier: "garage.addPart") {
                    present(.addItem)
                }
            }
            if model.library.items.isEmpty {
                Text(GarageCopy.partsEmpty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.library.items) { item in
                    itemCard(item)
                }
            }
        }
    }

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(GarageCopy.todos)
                .padding(.top, 8)
                .accessibilityIdentifier("garage.todos")
            if model.isEditing {
                todoComposer
            }
            if model.library.todos.isEmpty {
                Text(GarageCopy.todosEmpty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.library.todos) { todo in
                    todoCard(todo)
                }
            }
        }
    }

    private var todoComposer: some View {
        HStack(spacing: 12) {
            TextField(GarageCopy.todoPlaceholder, text: $todoDraft)
                .textFieldStyle(.plain)
                .font(.body)
                .submitLabel(.done)
                .onSubmit(commitTodo)
                .accessibilityIdentifier("garage.todo.field")
            Button(GarageCopy.add, action: commitTodo)
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(canAddTodo ? Color.primary : Color.secondary)
                .disabled(!canAddTodo)
                .accessibilityIdentifier("garage.addTodo")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(JobSheetChrome.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22))
        }
    }

    private var confirmedFacts: [GarageFact] {
        model.library.facts.filter(\.isConfirmed)
    }

    private var pendingFacts: [GarageFact] {
        model.library.facts.filter { !$0.isConfirmed }
    }

    private var canAddTodo: Bool {
        !todoDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func present(_ next: GarageSheet) {
        formDetent = .large
        sheet = next
    }

    private func commitTodo() {
        if model.addTodo(title: todoDraft) {
            todoDraft = ""
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func addButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.body)
            .foregroundStyle(.primary)
            .accessibilityIdentifier(identifier)
    }

    private func factCard(_ fact: GarageFact) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(fact.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(fact.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(fact.isConfirmed ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.trailing)
            }
            if model.isEditing {
                HStack(spacing: 16) {
                    Button(GarageCopy.change) { present(.editFact(fact.id)) }
                        .accessibilityIdentifier("garage.fact.change.\(fact.id)")
                    Button(GarageCopy.remove) { model.removeFact(id: fact.id) }
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("garage.fact.remove.\(fact.id)")
                }
                .buttonStyle(.plain)
                .font(.subheadline)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JobSheetChrome.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("garage.row.\(fact.id)")
    }

    private func photoCard(_ photo: GaragePhoto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail(fileName: photo.fileName, height: 120)
            if !photo.caption.isEmpty {
                Text(photo.caption)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            if model.isEditing {
                Button(GarageCopy.remove) { model.removePhoto(id: photo.id) }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("garage.photo.remove.\(photo.id)")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JobSheetChrome.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("garage.photo.\(photo.id)")
    }

    private func itemCard(_ item: GarageItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let fileName = item.photoFileName {
                    thumbnail(fileName: fileName, height: 56)
                        .frame(width: 56)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                    if !item.note.isEmpty {
                        Text(item.note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if model.isEditing {
                Button(GarageCopy.remove) { model.removeItem(id: item.id) }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("garage.item.remove.\(item.id)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JobSheetChrome.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("garage.item.\(item.id)")
    }

    private func todoCard(_ todo: GarageTodo) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                model.setTodoDone(id: todo.id, isDone: !todo.isDone)
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("garage.todo.toggle.\(todo.id)")
            .accessibilityLabel(todo.isDone ? "Done, \(todo.title)" : "Not done, \(todo.title)")
            Text(todo.title)
                .font(.subheadline)
                .strikethrough(todo.isDone)
                .foregroundStyle(todo.isDone ? Color.secondary : Color.primary)
            Spacer(minLength: 8)
            if model.isEditing {
                Button(GarageCopy.remove) { model.removeTodo(id: todo.id) }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("garage.todo.remove.\(todo.id)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(JobSheetChrome.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("garage.todo.\(todo.id)")
    }

    @ViewBuilder
    private func thumbnail(fileName: String, height: CGFloat) -> some View {
        if let data = model.imageData(fileName: fileName), let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.91))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay {
                    Text("Photo missing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

private enum GarageSheet: Identifiable {
    case addFact
    case editFact(String)
    case addPhoto
    case addItem

    var id: String {
        switch self {
        case .addFact: "add-fact"
        case .editFact(let factID): "edit-\(factID)"
        case .addPhoto: "add-photo"
        case .addItem: "add-item"
        }
    }
}

extension GaragePreview {
    fileprivate var openingSheet: GarageSheet? {
        switch self {
        case .view, .edit, .todos: nil
        case .addPhoto: .addPhoto
        case .addPart: .addItem
        }
    }
}

/// White sheet. Medium and large detents: the system scrim gets darker as the sheet is pulled higher.
private struct GarageEditorSheet: View {
    var sheet: GarageSheet
    var model: GarageModel
    var onClose: () -> Void

    @State private var label: String
    @State private var value: String
    @State private var caption = ""
    @State private var itemName = ""
    @State private var itemNote = ""
    @State private var imageData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var pickError: String?

    init(sheet: GarageSheet, model: GarageModel, onClose: @escaping () -> Void) {
        self.sheet = sheet
        self.model = model
        self.onClose = onClose
        if case .editFact(let id) = sheet, let fact = model.library.facts.first(where: { $0.id == id }) {
            _label = State(initialValue: fact.label)
            _value = State(initialValue: fact.value)
        } else {
            _label = State(initialValue: "")
            _value = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    formFields
                    if let pickError {
                        Text(pickError)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .preferredColorScheme(.light)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                await loadPickedPhoto(item)
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(
                onCapture: { data in
                    imageData = data
                    pickError = nil
                    showCamera = false
                },
                onCancel: { showCamera = false }
            )
            .presentationBackground(Color.white)
            .presentationCornerRadius(CGFloat(JobSheetLayout.topCornerRadius))
            .presentationDetents([.large])
        }
    }

    private var sheetHeader: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .accessibilityIdentifier("garage.form.title")
            HStack {
                Button(GarageCopy.cancel, action: onClose)
                    .buttonStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("garage.form.cancel")
                Spacer()
                Button(GarageCopy.save, action: save)
                    .buttonStyle(.plain)
                    .font(.body)
                    .foregroundStyle(canSave ? Color.primary : Color.secondary)
                    .disabled(!canSave)
                    .accessibilityIdentifier(saveIdentifier)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var formFields: some View {
        switch sheet {
        case .addFact, .editFact:
            labeledField(
                GarageCopy.factWhat,
                text: $label,
                placeholder: GarageCopy.factWhatPlaceholder,
                identifier: "garage.fact.label"
            )
            labeledField(
                GarageCopy.factValue,
                text: $value,
                placeholder: GarageCopy.factValuePlaceholder,
                identifier: "garage.fact.value",
                onSubmit: save
            )
        case .addPhoto:
            photoChoices(libraryIdentifier: "garage.photo.library", cameraIdentifier: "garage.photo.camera")
            photoPreview
            labeledField(
                GarageCopy.captionLabel,
                text: $caption,
                placeholder: GarageCopy.captionPlaceholder,
                identifier: "garage.photo.caption"
            )
        case .addItem:
            labeledField(
                GarageCopy.partName,
                text: $itemName,
                placeholder: GarageCopy.partNamePlaceholder,
                identifier: "garage.item.name"
            )
            labeledField(
                GarageCopy.partNote,
                text: $itemNote,
                placeholder: GarageCopy.partNotePlaceholder,
                identifier: "garage.item.note"
            )
            Text(GarageCopy.addPhotoOptional)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            photoChoices(libraryIdentifier: "garage.item.library", cameraIdentifier: "garage.item.camera")
            photoPreview
        }
    }

    private var title: String {
        switch sheet {
        case .addFact: GarageCopy.addFactTitle
        case .editFact: GarageCopy.editFactTitle
        case .addPhoto: GarageCopy.addPhotoTitle
        case .addItem: GarageCopy.addPartTitle
        }
    }

    private var saveIdentifier: String {
        switch sheet {
        case .addFact, .editFact: "garage.fact.save"
        case .addPhoto: "garage.photo.save"
        case .addItem: "garage.item.save"
        }
    }

    private var canSave: Bool {
        switch sheet {
        case .addFact, .editFact:
            return !trimmed(label).isEmpty && !trimmed(value).isEmpty
        case .addPhoto:
            return imageData != nil
        case .addItem:
            return !trimmed(itemName).isEmpty
        }
    }

    private func save() {
        let saved: Bool
        switch sheet {
        case .addFact:
            saved = model.addFact(label: label, value: value)
        case .editFact(let id):
            saved = model.updateFact(id: id, label: label, value: value)
        case .addPhoto:
            guard let imageData else { return }
            saved = model.addPhoto(caption: caption, jpeg: imageData)
        case .addItem:
            saved = model.addItem(name: itemName, note: itemNote, jpeg: imageData)
        }
        if saved {
            onClose()
        }
    }

    private func labeledField(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        identifier: String,
        onSubmit: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.body)
                .submitLabel(onSubmit == nil ? .next : .done)
                .onSubmit { onSubmit?() }
                .padding(12)
                .background(JobSheetChrome.fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(JobSheetChrome.fieldStroke, lineWidth: 1)
                }
                .accessibilityIdentifier(identifier)
        }
    }

    private func photoChoices(libraryIdentifier: String, cameraIdentifier: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text(GarageCopy.choosePhoto)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(libraryIdentifier)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(GarageCopy.takePhoto) { showCamera = true }
                    .buttonStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier(cameraIdentifier)
            }
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("garage.form.preview")
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let picked = try await item.loadTransferable(type: GaragePickedImage.self) else {
                pickError = GarageCopy.photoUnreadable
                return
            }
            imageData = GaragePickedImage.jpegData(from: picked.data) ?? picked.data
            pickError = nil
        } catch {
            pickError = GarageCopy.photoUnreadable
        }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct GaragePickedImage: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            GaragePickedImage(data: data)
        }
    }

    static func jpegData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: 0.85)
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.onCapture = onCapture
        context.coordinator.onCancel = onCancel
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var onCapture: (Data) -> Void
        var onCancel: () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.85)
            if let data {
                onCapture(data)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

#Preview("Garage") {
    GarageScreen(onClose: {}, preview: .view)
}

#Preview("Garage edit") {
    GarageScreen(onClose: {}, preview: .edit)
}

#Preview("Add a photo") {
    GarageScreen(onClose: {}, preview: .addPhoto)
}

#Preview("Add a part") {
    GarageScreen(onClose: {}, preview: .addPart)
}

#Preview("To-do") {
    GarageScreen(onClose: {}, preview: .todos)
}
