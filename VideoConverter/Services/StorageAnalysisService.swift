// StorageAnalysisService.swift
// VideoConverter

import Foundation
import Photos
import AVFoundation

final class StorageAnalysisService {

    private let cacheFileName = "storage_analysis.json"
    private let fileManager = FileManager.default

    private var cacheURL: URL? {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[StorageAnalysisService] No documents directory")
            return nil
        }
        let url = documentsURL.appendingPathComponent(cacheFileName)
        return url
    }

    func loadCached() async -> StorageAnalysis? {
        guard let url = cacheURL else {
            print("[StorageAnalysisService] No cache URL")
            return nil
        }

        guard fileManager.fileExists(atPath: url.path) else {
            print("[StorageAnalysisService] Cache file does not exist at \(url.path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let result = try decoder.decode(StorageAnalysis.self, from: data)
            print("[StorageAnalysisService] Loaded from cache: \(result.totalCount) items")
            return result
        } catch {
            print("[StorageAnalysisService] Failed to decode cache: \(error)")
            return nil
        }
    }

    func save(_ analysis: StorageAnalysis) async {
        guard let url = cacheURL else {
            print("[StorageAnalysisService] No cache URL for save")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(analysis)
            try data.write(to: url, options: .atomic)
            print("[StorageAnalysisService] Saved \(analysis.totalCount) items")
        } catch {
            print("[StorageAnalysisService] Failed to save: \(error)")
        }
    }

    func scan(
        authorizationStatus: PHAuthorizationStatus,
        progressHandler: (@MainActor (Int) -> Void)? = nil
    ) async -> StorageAnalysis? {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return nil
        }

        var photoBytes: Int64 = 0
        var livePhotoBytes: Int64 = 0
        var hevcVideoBytes: Int64 = 0
        var nonHevcVideoBytes: Int64 = 0
        var photoCount = 0
        var livePhotoCount = 0
        var hevcVideoCount = 0
        var nonHevcVideoCount = 0

        let images: PHFetchResult<PHAsset> = await Task.detached {
            let o = PHFetchOptions()
            o.includeHiddenAssets = false
            return PHAsset.fetchAssets(with: .image, options: o)
        }.value

        let videos: PHFetchResult<PHAsset> = await Task.detached {
            let o = PHFetchOptions()
            o.includeHiddenAssets = false
            return PHAsset.fetchAssets(with: .video, options: o)
        }.value

        var processed = 0

        for i in 0..<images.count {
            let asset = images.object(at: i)
            photoBytes += await getImageFileSize(for: asset)
            photoCount += 1
            processed += 1
            let currentCount = processed
            Task { @MainActor in
                progressHandler?(currentCount)
            }
        }

        for i in 0..<videos.count {
            let asset = videos.object(at: i)
            let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
            let size = await getVideoFileSize(for: asset)

            if isLivePhoto {
                livePhotoBytes += size
                livePhotoCount += 1
            } else {
                let isHEVC = await checkIsHEVC(for: asset)
                if isHEVC {
                    hevcVideoBytes += size
                    hevcVideoCount += 1
                } else {
                    nonHevcVideoBytes += size
                    nonHevcVideoCount += 1
                }
            }
            processed += 1
            let currentCount = processed
            Task { @MainActor in
                progressHandler?(currentCount)
            }
        }

        let analysis = StorageAnalysis(
            photoCount: photoCount,
            livePhotoCount: livePhotoCount,
            hevcVideoCount: hevcVideoCount,
            nonHevcVideoCount: nonHevcVideoCount,
            photoBytes: photoBytes,
            livePhotoBytes: livePhotoBytes,
            hevcVideoBytes: hevcVideoBytes,
            nonHevcVideoBytes: nonHevcVideoBytes,
            scannedAt: Date()
        )

        await save(analysis)

        return analysis
    }

    private nonisolated func getImageFileSize(for asset: PHAsset) async -> Int64 {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: Int64(data?.count ?? 0))
            }
        }
    }

    private nonisolated func getVideoFileSize(for asset: PHAsset) async -> Int64 {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
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

    private nonisolated func checkIsHEVC(for asset: PHAsset) async -> Bool {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard let avAsset else {
                    continuation.resume(returning: false)
                    return
                }
                Task.detached {
                    do {
                        let tracks = try await avAsset.loadTracks(withMediaType: .video)
                        guard let videoTrack = tracks.first else {
                            await MainActor.run { continuation.resume(returning: false) }
                            return
                        }
                        let formatDescriptions = (try? await videoTrack.load(.formatDescriptions)) ?? []
                        let isHEVC = formatDescriptions.contains {
                            let sub = CMFormatDescriptionGetMediaSubType($0)
                            return sub == kCMVideoCodecType_HEVC || sub == kCMVideoCodecType_HEVCWithAlpha
                        }
                        await MainActor.run { continuation.resume(returning: isHEVC) }
                    } catch {
                        await MainActor.run { continuation.resume(returning: false) }
                    }
                }
            }
        }
    }
}
