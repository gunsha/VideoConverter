// VideoDetailsList.swift
// VideoConverter

import SwiftUI
import Photos

struct VideoDetailsList: View {
    let asset: VideoAsset

    var body: some View {
        VStack(spacing: 0) {
            CollapsibleSection(title: "Camera details", isInitiallyCollapsed: true) {
                VStack(alignment: .leading, spacing: 8) {
                    if let cameraMake = asset.cameraMake {
                        DetailRow(label: "Camera", value: cameraMake)
                    }
                    if let cameraModel = asset.cameraModel {
                        DetailRow(label: "Camera model", value: cameraModel)
                    }
                    if let lensMake = asset.lensMake {
                        DetailRow(label: "Lens make", value: lensMake)
                    }
                    if let lensModel = asset.lensModel {
                        DetailRow(label: "Lens model", value: lensModel)
                    }
                    if let software = asset.software {
                        DetailRow(label: "Software", value: software)
                    }
                    if asset.cameraMake == nil && asset.cameraModel == nil &&
                        asset.lensMake == nil && asset.lensModel == nil && asset.software == nil {
                        Text("No device info available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
