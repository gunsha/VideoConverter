// PhotoLibraryService.swift
// VideoConverter

import Foundation
import Photos
import AVFoundation
import CoreLocation
import ImageIO

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

        let maxConcurrent = 15
        let totalCount = phAssets.count
        var results: [VideoAsset] = []
        var lastReportedCount = 0
        let progressBatch = max(10, totalCount / 20)

        for batchStart in stride(from: 0, to: totalCount, by: maxConcurrent) {
            let batchEnd = min(batchStart + maxConcurrent, totalCount)
            let batch = Array(phAssets[batchStart..<batchEnd])

            let batchResults = await withTaskGroup(of: VideoAsset?.self) { group -> [VideoAsset] in
                for phAsset in batch {
                    group.addTask {
                        await self.buildVideoAsset(from: phAsset)
                    }
                }
                var assets: [VideoAsset] = []
                for await result in group {
                    if let asset = result {
                        assets.append(asset)
                    }
                }
                return assets
            }

            results.append(contentsOf: batchResults)

            let currentCount = results.count
            if currentCount - lastReportedCount >= progressBatch {
                lastReportedCount = currentCount
                Task { @MainActor in
                    progressHandler?(currentCount)
                }
            }
        }

        if results.count > lastReportedCount {
            Task { @MainActor in
                progressHandler?(results.count)
            }
        }

        return results.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
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
        let mediaCharacteristics = (try? await videoTrack.load(.mediaCharacteristics)) ?? []
        let isHDR = mediaCharacteristics.contains(.containsHDRVideo)

        let fileSize = await getVideoFileSize(for: phAsset)
        let filename = getFilename(for: phAsset)
        
        // Extract lens and camera metadata
        let metadata = await extractLensMetadataFromAVAsset(avAsset)

        return await VideoAsset(
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
            isFavorite: phAsset.isFavorite,
            lensMake: metadata.lensMake,
            lensModel: metadata.lensModel,
            cameraMake: metadata.cameraMake,
            cameraModel: metadata.cameraModel,
            software: metadata.software
        )
    }
    
    private nonisolated func extractLensMetadataFromAVAsset(_ avAsset: AVAsset) async -> (lensMake: String?, lensModel: String?, cameraMake: String?, cameraModel: String?, software: String?) {
        var lensMake: String?
        var lensModel: String?
        var cameraMake: String?
        var cameraModel: String?
        var software: String?
        
        // Debug: Collect all metadata keys
        var allMetadataKeys: [String] = []
        
        do {
            // Try common metadata first
            let commonMetadata = try await avAsset.load(.commonMetadata)
            for item in commonMetadata {
                guard let key = item.commonKey?.rawValue else { continue }
                allMetadataKeys.append("common:\(key)")
                let value = try? await item.load(.stringValue)
                switch key {
                case "make":
                    if cameraMake == nil { cameraMake = value }
                case "model":
                    if cameraModel == nil { cameraModel = value }
                case "software":
                    if software == nil { software = value }
                case "lensMake":
                    if lensMake == nil { lensMake = value }
                case "lensModel":
                    if lensModel == nil { lensModel = value }
                default:
                    break
                }
            }
            
            // Also try QuickTime metadata
            let quickTimeMetadata = try await avAsset.load(.metadata)
            for item in quickTimeMetadata {
                // Check by identifier
                if let identifier = item.identifier {
                    allMetadataKeys.append("qt:\(identifier.rawValue)")
                    let value = try? await item.load(.stringValue)
                    switch identifier {
                    case .quickTimeMetadataMake:
                        if cameraMake == nil { cameraMake = value }
                    case .quickTimeMetadataModel:
                        if cameraModel == nil { cameraModel = value }
                    case .quickTimeMetadataSoftware:
                        if software == nil { software = value }
                    default:
                        break
                    }
                }
                
                // Check by key string (for lens-specific keys)
                if let key = item.key as? String {
                    allMetadataKeys.append("key:\(key)")
                    let value = try? await item.load(.stringValue)
                    switch key {
                    case "com.apple.quicktime.lens.make":
                        if lensMake == nil { lensMake = value }
                    case "com.apple.quicktime.lens.model":
                        if lensModel == nil { lensModel = value }
                    case "com.apple.quicktime.make":
                        if cameraMake == nil { cameraMake = value }
                    case "com.apple.quicktime.model":
                        if cameraModel == nil { cameraModel = value }
                    case "com.apple.quicktime.software":
                        if software == nil { software = value }
                    default:
                        break
                    }
                }
            }
            
            // Try video track metadata as well
            if let videoTrack = try await avAsset.loadTracks(withMediaType: .video).first {
                let trackMetadata = try await videoTrack.load(.metadata)
                for item in trackMetadata {
                    if let key = item.key as? String {
                        allMetadataKeys.append("track:\(key)")
                        let value = try? await item.load(.stringValue)
                        switch key {
                        case "com.apple.quicktime.camera.lens_model":
                            if lensModel == nil { lensModel = value }
                        case "com.apple.quicktime.lens.make":
                            if lensMake == nil { lensMake = value }
                        case "com.apple.quicktime.lens.model":
                            if lensModel == nil { lensModel = value }
                        case "com.apple.quicktime.make":
                            if cameraMake == nil { cameraMake = value }
                        case "com.apple.quicktime.model":
                            if cameraModel == nil { cameraModel = value }
                        case "com.apple.quicktime.software":
                            if software == nil { software = value }
                        default:
                            break
                        }
                    }
                }
            }
        } catch {
            // Ignore errors
        }
        
        return (lensMake, lensModel, cameraMake, cameraModel, software)
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
    
    private nonisolated func loadAVAssetForMetadata(for phAsset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
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

    private nonisolated func getFilename(for phAsset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: phAsset)
        if let videoResource = resources.first(where: { $0.type == .video }) {
            return videoResource.originalFilename
        }
        if let resource = resources.first {
            return resource.originalFilename
        }
        return "video_\(phAsset.localIdentifier)"
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
