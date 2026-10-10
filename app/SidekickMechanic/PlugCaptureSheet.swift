import PhotosUI
import SidekickCore
import SwiftUI
import UIKit

/// Library or camera, then a JPEG small enough for `PlugPhoto`.
struct PlugCaptureSheet: View {
    var onCapture: (PlugPhoto) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(StarterQuestion.whichConnector.text)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Close", action: { dismiss() })
                    .buttonStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("plug.close")
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text(GarageCopy.choosePhoto)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plug.library")

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(GarageCopy.takePhoto) {
                    showCamera = true
                }
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("plug.camera")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("plug.error")
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .sheet(isPresented: $showCamera) {
            PlugCameraPicker(
                onCapture: { data in
                    showCamera = false
                    deliver(data)
                },
                onCancel: { showCamera = false }
            )
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        do {
            guard let picked = try await item.loadTransferable(type: PickedPlugImage.self) else {
                errorMessage = GarageCopy.photoUnreadable
                return
            }
            deliver(picked.data)
        } catch {
            errorMessage = GarageCopy.photoUnreadable
        }
    }

    private func deliver(_ data: Data) {
        guard let image = UIImage(data: data), let photo = PlugJPEG.photo(from: image) else {
            errorMessage = GarageCopy.photoUnreadable
            return
        }
        errorMessage = nil
        onCapture(photo)
        dismiss()
    }
}

/// White 24pt sheet. The garage dim replaces the system grey and darkens as the sheet rises.
extension View {
    func plugCaptureSheet(
        isPresented: Binding<Bool>,
        onCapture: @escaping (PlugPhoto) -> Void
    ) -> some View {
        modifier(PlugCaptureSheetModifier(isPresented: isPresented, onCapture: onCapture))
    }
}

private struct PlugCaptureSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    var onCapture: (PlugPhoto) -> Void
    @State private var coverage = 0.0
    @State private var scrimVisible = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if scrimVisible {
                    GarageDim(coverage: coverage, identifier: "plug.dim", label: "Close plug check") {
                        isPresented = false
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: scrimVisible)
            .onChange(of: isPresented) { _, shown in
                if shown { scrimVisible = true }
            }
            .sheet(isPresented: $isPresented, onDismiss: { scrimVisible = false }) {
                PlugCaptureSheet(onCapture: onCapture)
                    .background {
                        GarageSheetPositionReader(coverage: $coverage)
                    }
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color.white)
                    .presentationCornerRadius(CGFloat(JobSheetLayout.topCornerRadius))
                    .preferredColorScheme(.light)
            }
    }
}

/// Re-encodes a picked image as JPEG and shrinks it until `PlugPhoto` accepts it.
private enum PlugJPEG {
    static func photo(from image: UIImage) -> PlugPhoto? {
        guard image.size.width >= 1, image.size.height >= 1 else { return nil }
        var edge: CGFloat = 1600
        var quality: CGFloat = 0.8
        for _ in 0..<6 {
            let fitted = fitted(image, maxEdge: edge)
            if let data = fitted.jpegData(compressionQuality: quality),
               let photo = PlugPhoto(jpegData: data) {
                return photo
            }
            edge = max(320, edge * 0.7)
            quality = max(0.4, quality - 0.15)
        }
        return nil
    }

    private static func fitted(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private struct PickedPlugImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickedPlugImage(data: data)
        }
    }
}

private struct PlugCameraPicker: UIViewControllerRepresentable {
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
