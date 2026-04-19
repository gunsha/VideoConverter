// PhotoLibraryService.swift
// VideoConverter

import Foundation
import Photos
import AVFoundation
import CoreLocation

// MARK: - PhotoLibraryService
final class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver {

    // MARK: Published state
    @MainActor var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private var libraryChangedHandler: (() -> Void)?

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    // MARK: - Authorization

    @MainActor
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status
    }

    // MARK: - Fetch all videos

    func fetchAllVideos(progressHandler: (@Sendable (Int) -> Void)? = nil) async -> [VideoAsset] {
        let phAssets = await Task.detached {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.includeHiddenAssets = false

            let result = PHAsset.fetchAssets(with: .video, options: fetchOptions)
            var assets: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in
                guard !asset.mediaSubtypes.contains(.photoLive) else { return }
                assets.append(asset)
            }
            return assets
        }.value

        return await withTaskGroup(of: VideoAsset?.self) { group -> [VideoAsset] in
            var count = 0
            for phAsset in phAssets {
                group.addTask {
                    await self.buildVideoAsset(from: phAsset)
                }
            }
            var assets: [VideoAsset] = []
            for await result in group {
                if let asset = result {
                    count += 1
                    let currentCount = count
                    Task { @MainActor in
                        progressHandler?(currentCount)
                    }
                    assets.append(asset)
                }
            }
            return assets.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        }
    }

    // MARK: - Fetch single asset by ID

    func fetchVideoAsset(by identifier: String) async -> VideoAsset? {
        guard let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            return nil
        }
        return await buildVideoAsset(from: phAsset)
    }

    // MARK: - Private helpers

    private nonisolated func buildVideoAsset(from phAsset: PHAsset) async -> VideoAsset? {
        guard let avAsset = await loadAVURLAsset(for: phAsset) else { return nil }

        // Load video tracks
        guard let tracks = try? await avAsset.loadTracks(withMediaType: .video),
              let videoTrack = tracks.first else { return nil }

        let formatDescriptions = (try? await videoTrack.load(.formatDescriptions)) ?? []
        let codec = codecName(from: formatDescriptions.first)
        let frameRate = (try? await videoTrack.load(.nominalFrameRate)).map(Double.init) ?? 30.0
        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? CGSize(width: phAsset.pixelWidth, height: phAsset.pixelHeight)
        let isHDR = videoTrack.hasMediaCharacteristic(.containsHDRVideo)

        let fileSize = await getVideoFileSize(for: phAsset)
        let filename = avAsset.url.lastPathComponent

        return VideoAsset(
            id: phAsset.localIdentifier,
            phAsset: phAsset,
            filename: filename,
            fileSize: fileSize,
            duration: phAsset.duration,
            creationDate: phAsset.creationDate,
            modificationDate: phAsset.modificationDate,
            resolution: naturalSize,
            frameRate: frameRate,
            codec: codec,
            isHDR: isHDR,
            locationCoordinate: phAsset.location?.coordinate,
            isFavorite: phAsset.isFavorite
        )
    }

    private nonisolated func loadAVURLAsset(for phAsset: PHAsset) async -> AVURLAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset as? AVURLAsset)
            }
        }
    }

    private nonisolated func getVideoFileSize(for phAsset: PHAsset) async -> Int64 {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
                guard let avAsset = avAsset as? AVURLAsset else {
                    continuation.resume(returning: 0)
                    return
                }
                Task.detached {
                    do {
                        let attrs = try FileManager.default.attributesOfItem(atPath: avAsset.url.path)
                        let fileSize = (attrs[.size] as? Int64) ?? 0
                        await MainActor.run { continuation.resume(returning: fileSize) }
                    } catch {
                        await MainActor.run { continuation.resume(returning: 0) }
                    }
                }
            }
        }
    }

    private nonisolated func codecName(from desc: CMFormatDescription?) -> String {
        guard let desc else { return "Unknown" }
        let sub = CMFormatDescriptionGetMediaSubType(desc)
        switch sub {
        case kCMVideoCodecType_H264:            return "H.264"
        case kCMVideoCodecType_MPEG4Video:      return "MPEG-4"
        case kCMVideoCodecType_AppleProRes422:  return "ProRes 422"
        case kCMVideoCodecType_AppleProRes4444: return "ProRes 4444"
        default:
            // Convert FourCC to string
            let bytes = [
                UInt8((sub >> 24) & 0xFF),
                UInt8((sub >> 16) & 0xFF),
                UInt8((sub >>  8) & 0xFF),
                UInt8((sub      ) & 0xFF),
            ]
            let str = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "?"
            return str
        }
    }

    // MARK: - Change observation

    func onLibraryChanged(_ handler: @escaping () -> Void) {
        libraryChangedHandler = handler
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.libraryChangedHandler?()
        }
    }
}
