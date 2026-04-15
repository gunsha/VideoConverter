// VideoRowView.swift
// VideoConverter

import SwiftUI
import Photos

struct VideoRowView: View {
    let asset: VideoAsset
    let isSelected: Bool
    var onThumbnailTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ThumbnailView(asset: asset.phAsset, size: CGSize(width: 84, height: 63))
                .onTapGesture {
                    onThumbnailTap?()
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(asset.formattedDuration)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.filename)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    // Codec badge
                    BadgeLabel(asset.codec, color: .orange)
                    // Resolution badge
                    BadgeLabel(asset.resolutionLabel, color: .blue)
                    // FPS
                    BadgeLabel(asset.frameRateLabel, color: .purple)
                }

                HStack(spacing: 8) {
                    Label(asset.formattedFileSize, systemImage: "doc.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let date = asset.creationDate {
                        Label(date.formatted(date: .abbreviated, time: .omitted),
                              systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Selection checkmark
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray4))
                .animation(.spring(duration: 0.2), value: isSelected)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Badge helper
private struct BadgeLabel: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}

#Preview {
    List {
        VideoRowView(asset: .preview, isSelected: false)
        VideoRowView(asset: .preview, isSelected: true)
    }
}

// MARK: - Preview stub
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
        locationCoordinate: nil,
        isFavorite: false
    )
}
