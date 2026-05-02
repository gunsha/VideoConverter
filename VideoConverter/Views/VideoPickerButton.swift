// VideoPickerButton.swift
// iOS 26+ | SwiftUI + PhotosUI
//
// Usage:
//   VideoPickerButton { identifier, url in
//       // Use identifier to fetch PHAsset:
//       //   let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
//       //   let asset  = result.firstObject
//       //
//       // Use url to load AVAsset:
//       //   let avAsset = AVURLAsset(url: url)
//   }

import SwiftUI
import PhotosUI
import Photos

// MARK: - Public result type

public struct VideoPickerResult {
    /// PHAsset local identifier — use with PHAsset.fetchAssets(withLocalIdentifiers:options:)
    public let localIdentifier: String
    /// File URL of the copied video — use with AVURLAsset(url:) to read metadata
    public let url: URL
}

// MARK: - View-model / coordinator

@Observable
final class VideoPickerViewModel {

    // Presented state
    var isPresented = false

    // Last successful pick
    var result: VideoPickerResult?

    // Error surfaced to the caller
    var error: VideoPickerError?

    // Internal loading flag
    private(set) var isLoading = false

    // Callback set by the button
    var onPick: ((VideoPickerResult) -> Void)?
    var onError: ((VideoPickerError) -> Void)?

    // Called by the UIViewControllerRepresentable coordinator
    @MainActor
    func handle(pickerResult: PHPickerResult) async {
        isLoading = true
        defer { isLoading = false }

        // 1. Resolve the local identifier (requires the .photoLibrary source type)
        guard let identifier = pickerResult.assetIdentifier else {
            let err = VideoPickerError.missingIdentifier
            error = err
            onError?(err)
            return
        }

        // 2. Load the video file URL via NSItemProvider
        do {
            let url = try await loadVideoURL(from: pickerResult.itemProvider)
            let output = VideoPickerResult(localIdentifier: identifier, url: url)
            result = output
            onPick?(output)
        } catch {
            let err = VideoPickerError.loadFailed(error)
            self.error = err
            onError?(err)
        }
    }

    // MARK: Private helpers

    private func loadVideoURL(from provider: NSItemProvider) async throws -> URL {
        // Check the provider supports movie UTI
        guard provider.hasItemConformingToTypeIdentifier("public.movie") else {
            throw VideoPickerError.notAVideo
        }

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: VideoPickerError.noURL)
                    return
                }

                // The system-provided URL is temporary; copy it to a stable location.
                do {
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: dest)
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Error type

public enum VideoPickerError: LocalizedError {
    case missingIdentifier
    case notAVideo
    case noURL
    case loadFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .missingIdentifier: "Could not read the photo library identifier."
        case .notAVideo:         "The selected item is not a video."
        case .noURL:             "The video file URL could not be resolved."
        case .loadFailed(let e): "Failed to load video: \(e.localizedDescription)"
        }
    }
}

// MARK: - PHPicker representable

struct VideoPHPicker: UIViewControllerRepresentable {

    @Binding var isPresented: Bool
    let viewModel: VideoPickerViewModel

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented, viewModel: viewModel) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter          = .videos          // videos only
        config.selectionLimit  = 1                // single selection
        config.preferredAssetRepresentationMode = .current
        // Keep assetIdentifier available (requires photoLibrary source)
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    // MARK: Coordinator

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {

        @Binding var isPresented: Bool
        let viewModel: VideoPickerViewModel

        init(isPresented: Binding<Bool>, viewModel: VideoPickerViewModel) {
            _isPresented = isPresented
            self.viewModel = viewModel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            isPresented = false
            guard let first = results.first else { return }
            Task { await viewModel.handle(pickerResult: first) }
        }
    }
}

// MARK: - Public Button component

/// Drop-in SwiftUI button that opens the photo library (videos only).
/// Callbacks fire on the main actor.
///
/// ```swift
/// VideoPickerButton { result in
///     print(result.localIdentifier)
///     print(result.url)
/// }
/// ```
public struct VideoPickerButton: View {

    // MARK: Init

    private let label: String
    private let onPick: (VideoPickerResult) -> Void
    private let onError: ((VideoPickerError) -> Void)?

    public init(
        label: String = "Select Video",
        onError: ((VideoPickerError) -> Void)? = nil,
        onPick: @escaping (VideoPickerResult) -> Void
    ) {
        self.label   = label
        self.onError = onError
        self.onPick  = onPick
    }

    // MARK: State

    @State private var viewModel = VideoPickerViewModel()

    // MARK: Body

    public var body: some View {
        Button {
            viewModel.onPick  = onPick
            viewModel.onError = onError
            viewModel.isPresented = true
        } label: {
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "video.badge.plus")
                }
                Text(viewModel.isLoading ? "Loading…" : label)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
        }
        .disabled(viewModel.isLoading)
        .sheet(isPresented: $viewModel.isPresented) {
            VideoPHPicker(isPresented: $viewModel.isPresented, viewModel: viewModel)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        VideoPickerButton(
            label: "Select Video",
            onError: { err in
                print("Error:", err.localizedDescription)
            },
            onPick: { result in
                print("Identifier:", result.localIdentifier)
                print("URL:", result.url)
            }
        )
        .padding(.horizontal)
    }
}