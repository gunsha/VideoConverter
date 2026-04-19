// VideoPreviewView.swift
// VideoConverter

import SwiftUI
import AVKit
import Photos
#if os(iOS)
import UIKit
#endif

struct VideoPreviewView: View {
    let asset: VideoAsset
    let onDismiss: () -> Void

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var volume: Float = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .overlay(alignment: .bottomTrailing) {
                        volumeControl
                            .padding(.trailing, 16)
                            .padding(.bottom, 60)
                    }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                    Text("Unable to load video")
                        .foregroundStyle(.white)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                player?.pause()
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            }
        }
        #if os(iOS)
        .statusBarHidden()
        #endif
        .task {
            await loadVideo()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(.white)
                .font(.body)

            Slider(value: $volume, in: 0...1)
                .frame(width: 100)
                .tint(.white)
                .onChange(of: volume) { _, newValue in
                    player?.volume = newValue
                    player?.isMuted = newValue == 0
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func loadVideo() async {
        guard let phAsset = asset.phAsset else {
            isLoading = false
            return
        }
        
        let opts = PHVideoRequestOptions()
        opts.version = .current
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: opts) { avAsset, _, _ in
                if let avAsset {
                    let playerItem = AVPlayerItem(asset: avAsset)
                    DispatchQueue.main.async {
                        self.player = AVPlayer(playerItem: playerItem)
                        self.player?.isMuted = true
                        self.isLoading = false
                        self.player?.play()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                }
                continuation.resume()
            }
        }
    }
}

#Preview {
    VideoPreviewView(asset: VideoPreviewView.preview) {}
}

private extension VideoPreviewView {
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
