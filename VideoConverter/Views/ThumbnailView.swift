// ThumbnailView.swift
// VideoConverter

import SwiftUI
import Photos

/// Async thumbnail loaded from PHImageManager with a shimmer placeholder.
struct ThumbnailView: View {
    let asset: PHAsset
    var size: CGSize = CGSize(width: 80, height: 60)

    @State private var image: UIImage?
    @State private var loading = true

    private var cornerRadius: CGFloat { 8 }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.systemGray5))
                    .frame(width: size.width, height: size.height)
                    .overlay {
                        Image(systemName: "video.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .shimmer(loading)
            }
        }
        .task(id: asset.localIdentifier) {
            image = await loadThumbnail()
            loading = false
        }
    }

    private func loadThumbnail() async -> UIImage? {
        await withCheckedContinuation { cont in
            let targetSize = CGSize(width: size.width * 3, height: size.height * 3)
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .opportunistic
            opts.resizeMode   = .fast
            opts.isNetworkAccessAllowed = false
            opts.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: opts
            ) { img, info in
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                if !isDegraded { cont.resume(returning: img) }
                // If degraded, wait for the next callback (opportunistic mode delivers twice)
            }
        }
    }
}

// MARK: - Shimmer modifier
private extension View {
    @ViewBuilder
    func shimmer(_ active: Bool) -> some View {
        if active {
            self.overlay(ShimmerView())
        } else {
            self
        }
    }
}

private struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let gradient = LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.25), location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(gradient)
                .offset(x: phase * geo.size.width * 2)
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
        .clipped()
    }
}
