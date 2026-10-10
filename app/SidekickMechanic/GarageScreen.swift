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
    @State private var editorCoverage = 0.9
    @State private var editorScrimVisible = false
    @Binding var coverage: Double
    private let preview: GaragePreview?
    var onClose: () -> Void

    init(
        onClose: @escaping () -> Void,
        preview: GaragePreview? = nil,
        coverage: Binding<Double> = .constant(0.9)
    ) {
        self.onClose = onClose
        self.preview = preview
        self._coverage = coverage
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
            sheetTopMarker("garage.sheetTop")
            header
            ScrollViewReader { proxy in
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
                            .id("garage.todos.anchor")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollContentBackground(.hidden)
                .onAppear { scrollToTodos(proxy) }
                .task { await scrollToTodosAfterLayout(proxy) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("garage.sheet")
        .background {
            GarageSheetPositionReader(coverage: $coverage)
        }
        .overlay {
            if editorScrimVisible {
                GarageDim(coverage: editorCoverage, identifier: "garage.form.dim", label: "Close") {
                    sheet = nil
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            if sheet != nil {
                editorScrimVisible = true
            }
        }
        .onChange(of: sheet?.id) { _, id in
            if id != nil {
                editorScrimVisible = true
            }
        }
        .sheet(item: $sheet, onDismiss: { editorScrimVisible = false }) { item in
            GarageEditorSheet(
                sheet: item,
                model: model,
                coverage: $editorCoverage,
                onClose: { sheet = nil }
            )
            .presentationDetents([.medium, .large], selection: $formDetent)
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.white)
            .presentationCornerRadius(CGFloat(JobSheetLayout.topCornerRadius))
            .preferredColorScheme(.light)
        }
    }

    private func scrollToTodos(_ proxy: ScrollViewProxy) {
        guard preview == .todos else { return }
        proxy.scrollTo("garage.todos.anchor", anchor: .top)
    }

    private func scrollToTodosAfterLayout(_ proxy: ScrollViewProxy) async {
        guard preview == .todos else { return }
        try? await Task.sleep(for: .milliseconds(100))
        scrollToTodos(proxy)
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
        .sheetHeaderClearance()
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
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12, alignment: .top),
                        GridItem(.flexible(), spacing: 12, alignment: .top),
                    ],
                    spacing: 12
                ) {
                    ForEach(model.library.photos) { photo in
                        photoCard(photo)
                    }
                }
                .clipped()
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
        VStack(alignment: .leading, spacing: 8) {
            TextField(GarageCopy.todoPlaceholder, text: $todoDraft)
                .textFieldStyle(.plain)
                .font(.body)
                .submitLabel(.done)
                .onSubmit(commitTodo)
                .accessibilityIdentifier("garage.todo.field")
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35))
                }
            addButton(GarageCopy.addTodo, identifier: "garage.addTodo", enabled: canAddTodo, action: commitTodo)
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
        editorCoverage = 0.9
        editorScrimVisible = true
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

    private func addButton(
        _ title: String,
        identifier: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(enabled ? 0.55 : 0.22), lineWidth: 1.5)
        }
        .disabled(!enabled)
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
            thumbnail(fileName: photo.fileName)
            if !photo.caption.isEmpty {
                Text(photo.caption)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    thumbnail(fileName: fileName)
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

    private func thumbnail(fileName: String) -> some View {
        let image: UIImage?
        if let data = model.imageData(fileName: fileName) {
            image = UIImage(data: data)
        } else {
            image = nil
        }
        return SquarePhoto(image: image, missingLabel: image == nil ? "Photo missing" : nil)
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

/// White add/edit sheet. Its own dim sits on the garage sheet and darkens as this sheet rises.
private struct GarageEditorSheet: View {
    var sheet: GarageSheet
    var model: GarageModel
    @Binding var coverage: Double
    var onClose: () -> Void
    @State private var cameraCoverage = 0.9
    @State private var cameraScrimVisible = false

    @State private var label: String
    @State private var value: String
    @State private var caption = ""
    @State private var itemName = ""
    @State private var itemNote = ""
    @State private var imageData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var pickError: String?

    init(
        sheet: GarageSheet,
        model: GarageModel,
        coverage: Binding<Double>,
        onClose: @escaping () -> Void
    ) {
        self.sheet = sheet
        self.model = model
        self._coverage = coverage
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
            sheetTopMarker("garage.formTop")
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("garage.form")
        .background {
            GarageSheetPositionReader(coverage: $coverage)
        }
        .overlay {
            if cameraScrimVisible {
                GarageDim(coverage: cameraCoverage, identifier: "garage.camera.dim", label: "Close camera") {
                    showCamera = false
                }
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                await loadPickedPhoto(item)
            }
        }
        .onChange(of: showCamera) { _, isShown in
            if isShown {
                cameraScrimVisible = true
            }
        }
        .sheet(isPresented: $showCamera, onDismiss: { cameraScrimVisible = false }) {
            CameraPicker(
                onCapture: { data in
                    imageData = data
                    pickError = nil
                    showCamera = false
                },
                onCancel: { showCamera = false }
            )
            .background {
                GarageSheetPositionReader(coverage: $cameraCoverage)
            }
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
        .sheetHeaderClearance()
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
                Button(GarageCopy.takePhoto) {
                    cameraCoverage = 0.9
                    cameraScrimVisible = true
                    showCamera = true
                }
                    .buttonStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier(cameraIdentifier)
            }
            if GarageStoreLocation.showsSamplePhoto() {
                Button {
                    imageData = Self.sampleJPEG()
                    pickError = nil
                } label: {
                    Text(GarageCopy.samplePhoto)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.55), lineWidth: 1.5)
                }
                .accessibilityIdentifier(
                    libraryIdentifier == "garage.photo.library" ? "garage.photo.sample" : "garage.item.sample"
                )
            }
        }
    }

    private static func sampleJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor(white: 0.45, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data([0xFF, 0xD8, 0xFF, 0xD9])
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let imageData, let image = UIImage(data: imageData) {
            SquarePhoto(image: image, cornerRadius: 12)
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

/// 1:1 box. The image is aspect-filled inside that box, then clipped.
/// A wide photo must not set the cell's width or it spills into the next card.
struct SquarePhoto: View {
    var image: UIImage?
    var cornerRadius: CGFloat = 8
    var missingLabel: String?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    photo(size: geo.size)
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func photo(size: CGSize) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            Color(white: 0.91)
                .frame(width: size.width, height: size.height)
                .overlay {
                    if let missingLabel {
                        Text(missingLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(4)
                    }
                }
        }
    }
}

/// Custom dim. The system sheet dim is a light grey, so the sheet turns that off
/// and this overlay tracks how high the sheet is pulled.
struct GarageDim: View {
    var coverage: Double
    var identifier: String
    var label: String
    var onTap: () -> Void

    var body: some View {
        Color.black
            .opacity(GarageScrim.opacity(coverage: coverage))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }
}

/// Reports sheet coverage and disables the system dim. Coverage is 0 at the bottom of the screen and 1 at the top.
struct GarageSheetPositionReader: UIViewControllerRepresentable {
    @Binding var coverage: Double

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onCoverage = { next in
            coverage = next
        }
        controller.undim()
    }

    final class Controller: UIViewController {
        var onCoverage: ((Double) -> Void)?
        private var lastSent = -1.0

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            refresh()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            refresh()
        }

        func refresh() {
            undim()
            publish()
        }

        func undim() {
            var current: UIViewController? = self
            while let controller = current {
                if let sheet = controller.sheetPresentationController {
                    sheet.largestUndimmedDetentIdentifier = .large
                    return
                }
                current = controller.parent
            }
        }

        private func publish() {
            guard let window = view.window else { return }
            let height = window.bounds.height
            guard height > 0 else { return }
            guard let source = sheetHostView ?? viewIfLoaded else { return }
            guard source.bounds.height > 0 else { return }
            let top = source.convert(CGPoint.zero, to: window).y
            let next = 1 - Double(top / height)
            guard abs(next - lastSent) > 0.004 else { return }
            lastSent = next
            onCoverage?(next)
        }

        private var sheetHostView: UIView? {
            var current: UIViewController? = self
            while let controller = current {
                if controller.sheetPresentationController != nil {
                    return controller.view
                }
                current = controller.parent
            }
            return nil
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
