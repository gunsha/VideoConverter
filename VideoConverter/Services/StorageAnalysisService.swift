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
        print("[StorageAnalysisService] Cache URL: \(url.path)")
        print("[StorageAnalysisService] File exists: \(fileManager.fileExists(atPath: url.path))")
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
            print("[StorageAnalysisService] Loaded from cache: \(result.totalCount) items, \(result.totalBytes) bytes")
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
            print("[StorageAnalysisService] Saved \(analysis.totalCount) items to \(url.path)")
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

        let total = images.count + videos.count
        var processed = 0

        for i in 0..<images.count {
            let asset = images.object(at: i)
            let resources = PHAssetResource.assetResources(for: asset)
            let isLivePhoto = resources.contains { resource in
                let t = resource.value(forKey: "type") as? Int
                return t == 3
            }
            if isLivePhoto {
                for resource in resources {
                    livePhotoBytes += (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
                }
                livePhotoCount += 1
            } else {
                for resource in resources where resource.type == .photo {
                    photoBytes += (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
                }
                photoCount += 1
            }
            processed += 1
            let currentCount = processed
            Task { @MainActor in
                progressHandler?(currentCount)
            }
        }

        for i in 0..<videos.count {
            let asset = videos.object(at: i)
            let resources = PHAssetResource.assetResources(for: asset)
            let size: Int64
            if let videoResource = resources.first(where: { $0.type == .video }) {
                size = (videoResource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
            } else {
                size = 0
            }

            let isHEVC = await checkIsHEVC(for: asset)
            if isHEVC {
                hevcVideoBytes += size
                hevcVideoCount += 1
            } else {
                nonHevcVideoBytes += size
                nonHevcVideoCount += 1
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
