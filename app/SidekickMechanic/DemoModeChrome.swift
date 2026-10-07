import SidekickCore
import SwiftUI
import UIKit

@MainActor
@Observable
final class DemoImageStore {
    var catalog: DemoCatalog?
    var images: [String: UIImage] = [:]
    var loadError: String?

    func load(from configuration: ChatClientConfiguration) async {
        loadError = nil
        do {
            let (data, response) = try await URLSession.shared.data(from: configuration.demoPhotosURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                loadError = "Demo catalog HTTP \(http.statusCode)"
                return
            }
            let decoded = try JSONDecoder().decode(DemoCatalog.self, from: data)
            catalog = decoded
            for photo in decoded.photos {
                let (imageData, _) = try await URLSession.shared.data(
                    from: configuration.demoImageURL(photoID: photo.photoID)
                )
                if let image = UIImage(data: imageData) {
                    images[photo.photoID] = image
                }
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct DemoModeChrome: View {
    @Bindable var model: ChatViewModel
    var store: DemoImageStore
    var configuration: ChatClientConfiguration
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactBar
            if isExpanded {
                expandedBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .task(id: model.isDemoMode) {
            guard model.isDemoMode else { return }
            if store.catalog == nil {
                await store.load(from: configuration)
            }
            if model.selectedDemoPhotoID == nil {
                model.selectedDemoPhotoID = store.catalog?.defaultPhotoID
                    ?? DemoLaunchOptions.defaultPhotoID
            }
        }
    }

    private var selectedPhoto: DemoPhotoInfo? {
        store.catalog?.photos.first { $0.photoID == model.selectedDemoPhotoID }
    }

    private var compactBar: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                DemoDataBadge()
                Text(selectedPhoto?.thumbnailLabel ?? "Demo")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(model.highlightStyle.pickerLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("demo.banner")
        .accessibilityLabel(
            isExpanded
                ? "Hide demo options"
                : "Show demo options. \(selectedPhoto?.thumbnailLabel ?? "Demo"). \(model.highlightStyle.pickerLabel)."
        )
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Highlights are scripted. Not your truck.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let loadError = store.loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            photoPicker
            stylePicker

            if let photo = selectedPhoto, photo.shareAlike {
                Text("This photo is CC BY-SA 3.0. Credit the author if you share a screenshot.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("demo.shareAlike")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var photoPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.catalog?.photos ?? []) { photo in
                    Button {
                        model.selectedDemoPhotoID = photo.photoID
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let image = store.images[photo.photoID] {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 60)
                                    .clipped()
                            } else {
                                Color.secondary.opacity(0.2)
                                    .frame(width: 88, height: 60)
                            }
                            Text(photo.thumbnailLabel)
                                .font(.caption2)
                                .lineLimit(2)
                                .frame(width: 88, alignment: .leading)
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    model.selectedDemoPhotoID == photo.photoID
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.3),
                                    lineWidth: model.selectedDemoPhotoID == photo.photoID ? 2 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("demo.photo.\(photo.photoID)")
                    .accessibilityLabel("Demo photo \(photo.thumbnailLabel)")
                }
            }
        }
        .accessibilityIdentifier("demo.photoPicker")
    }

    private var stylePicker: some View {
        Picker("Highlight style", selection: $model.highlightStyle) {
            ForEach(DemoHighlightStyle.allCases, id: \.self) { style in
                Text(style.pickerLabel).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("demo.stylePicker")
    }
}

struct DemoConfirmBar: View {
    var onYes: () -> Void
    var onNotThis: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Is this it?")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Button("Yes", action: onYes)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("demo.confirm.yes")
                Button("Not this", action: onNotThis)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("demo.confirm.notThis")
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("demo.confirmBar")
    }
}

func postDemoFeedback(
    configuration: ChatClientConfiguration,
    photoID: String,
    partID: String,
    action: DemoConfirmDecision
) {
    var request = URLRequest(url: configuration.demoFeedbackURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(
        DemoFeedbackBody(photoID: photoID, partID: partID, action: action)
    )
    URLSession.shared.dataTask(with: request) { _, _, error in
        if let error {
            print("demo confirm tap log failed: \(error.localizedDescription)")
        } else {
            print("demo confirm tap photo_id=\(photoID) part_id=\(partID) action=\(action.rawValue)")
        }
    }.resume()
}
