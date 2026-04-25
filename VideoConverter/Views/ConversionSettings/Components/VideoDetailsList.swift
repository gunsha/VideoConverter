// VideoDetailsList.swift
// VideoConverter

import SwiftUI
import Photos

struct VideoDetailsList: View {
    let asset: VideoAsset

    @State private var cameraMake: String?
    @State private var cameraModel: String?
    @State private var lensMake: String?
    @State private var lensModel: String?
    @State private var software: String?
    @State private var isLoadingMetadata = false

    init(asset: VideoAsset) {
        self.asset = asset
        _cameraMake = State(initialValue: asset.cameraMake)
        _cameraModel = State(initialValue: asset.cameraModel)
        _lensMake = State(initialValue: asset.lensMake)
        _lensModel = State(initialValue: asset.lensModel)
        _software = State(initialValue: asset.software)
        
        let hasAny = asset.cameraMake != nil || asset.cameraModel != nil || asset.lensMake != nil || asset.lensModel != nil || asset.software != nil
        _isLoadingMetadata = State(initialValue: !hasAny && asset.phAsset != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            CollapsibleSection(title: "Camera details", isInitiallyCollapsed: true) {
                VStack(alignment: .leading, spacing: 8) {
                    if isLoadingMetadata {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        if let cameraMake = cameraMake {
                            DetailRow(label: "Camera", value: cameraMake)
                        }
                        if let cameraModel = cameraModel {
                            DetailRow(label: "Camera model", value: cameraModel)
                        }
                        if let lensMake = lensMake {
                            DetailRow(label: "Lens make", value: lensMake)
                        }
                        if let lensModel = lensModel {
                            DetailRow(label: "Lens model", value: lensModel)
                        }
                        if let software = software {
                            DetailRow(label: "Software", value: software)
                        }
                        if cameraMake == nil && cameraModel == nil &&
                            lensMake == nil && lensModel == nil && software == nil {
                            Text("No device info available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task {
            guard isLoadingMetadata, let phAsset = asset.phAsset else { return }
            let metadata = await PhotoLibraryService.fetchCameraMetadata(for: phAsset)
            cameraMake = metadata.cameraMake
            cameraModel = metadata.cameraModel
            lensMake = metadata.lensMake
            lensModel = metadata.lensModel
            software = metadata.software
            isLoadingMetadata = false
        }
    }
}

struct CollapsibleSection<Content: View>: View {
    let title: String
    var isInitiallyCollapsed: Bool
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool

    init(title: String, isInitiallyCollapsed: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.isInitiallyCollapsed = isInitiallyCollapsed
        self.content = content
        _isExpanded = State(initialValue: !isInitiallyCollapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Color(.systemGray6))
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    List {
        VideoDetailsList(asset: .preview)
    }
}

private extension VideoAsset {
    static let preview = VideoAsset(
        id: "preview",
        phAsset: PHAsset(),
        filename: "IMG_4512.MOV",
        fileSize: 248 * 1_048_576,
        duration: 127,
        creationDate: Date(),
        modificationDate: Date(),
        resolution: CGSize(width: 1920, height: 1080),
        frameRate: 30,
        codec: "H.264",
        isHDR: false,
        locationCoordinate: nil,
        isFavorite: false
    )
}
