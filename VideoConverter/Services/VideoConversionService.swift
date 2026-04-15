// VideoConversionService.swift
// VideoConverter

import Foundation
import UIKit
import AVFoundation
import Photos
import CoreLocation

// MARK: - Errors

enum ConversionError: LocalizedError {
    case assetLoadFailed
    case exportSessionCreationFailed
    case exportFailed(String)
    case noVideoTrack
    case insufficientStorage

    var errorDescription: String? {
        switch self {
        case .assetLoadFailed:              return "Could not load the video from your library."
        case .exportSessionCreationFailed:  return "Could not create an export session."
        case .exportFailed(let reason):     return "Export failed: \(reason)"
        case .noVideoTrack:                 return "The video has no video track."
        case .insufficientStorage:          return "Not enough storage space to complete the conversion."
        }
    }
}

// MARK: - VideoConversionService

/// Handles HEVC transcoding and saving converted files back to the photo library.
final class VideoConversionService {

    static let shared = VideoConversionService()
    private init() {}

    // MARK: - Conversion

    /// Converts a video to HEVC, reporting progress via `progressHandler` (called on MainActor).
    /// Returns the temporary output URL on success.
    func convert(
        job: ConversionJob,
        progressHandler: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {
        // Thermal guard
        let thermal = ProcessInfo.processInfo.thermalState
        guard thermal != .serious && thermal != .critical else {
            throw ConversionError.exportFailed("Device is too hot. Please wait and try again.")
        }

        // Storage pre-check
        let estimated = MetadataService.estimatedOutputBytes(
            sourceBytes: job.sourceAsset.fileSize,
            sourceResolution: job.sourceAsset.resolution,
            sourceFPS: job.sourceAsset.frameRate,
            targetResolution: job.targetResolution,
            targetFPS: job.targetFrameRate
        )
        try checkStorageSpace(estimatedBytes: max(estimated * 2, 50_000_000))

        // Duplicate guard
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        // Build and run the export session
        let session = try await createExportSession(for: job.sourceAsset.phAsset)

        session.outputURL = tempURL
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = false

        // Apply video composition if downscaling or changing FPS
        let sourceRes = job.sourceAsset.resolution
        let targetRes = job.targetResolution
        let targetFPS = job.targetFrameRate
        let sourceFPS = job.sourceAsset.frameRate

        let needsComposition = targetRes.width < sourceRes.width - 1 || targetFPS < sourceFPS - 0.5
        if needsComposition {
            if let composition = try await buildVideoComposition(
                asset: session.asset,
                targetResolution: targetRes,
                targetFPS: targetFPS
            ) {
                session.videoComposition = composition
            }
        }

        // Carry across any embedded metadata (title, description, etc.)
        if let existing = try? await session.asset.load(.commonMetadata) {
            session.metadata = existing
        }

        // Poll progress on MainActor
        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                progressHandler(Double(session.progress))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        // Background task so iOS doesn't kill us mid-export
        class TaskManager: @unchecked Sendable {
            var taskID: UIBackgroundTaskIdentifier = .invalid
        }
        let manager = TaskManager()
        manager.taskID = UIApplication.shared.beginBackgroundTask(withName: "HEVCConvert-\(job.id)") {
            session.cancelExport()
            UIApplication.shared.endBackgroundTask(manager.taskID)
        }
        defer { UIApplication.shared.endBackgroundTask(manager.taskID) }

        // Run the export using the modern async API (iOS 18+)
        try await session.export(to: tempURL, as: .mov)

        progressTask.cancel()
        await MainActor.run { progressHandler(1.0) }

        return tempURL
    }

    // MARK: - Save to library

    /// Saves the converted file to the photo library, preserving original metadata.
    /// Returns the new asset's local identifier.
    @discardableResult
    func saveToPhotoLibrary(url: URL, originalAsset: VideoAsset) async throws -> String {
        var placeholderID: String?

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let opts = PHAssetResourceCreationOptions()
                let stem = (originalAsset.filename as NSString).deletingPathExtension
                let ext  = (originalAsset.filename as NSString).pathExtension
                opts.originalFilename = "\(stem)_HEVC.\(ext.isEmpty ? "mov" : ext)"

                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: opts)
                request.creationDate = originalAsset.creationDate
                request.isFavorite   = originalAsset.isFavorite
                if let coord = originalAsset.locationCoordinate {
                    request.location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                }

                // Replicate album membership
                let sourceResult = PHAsset.fetchAssets(
                    withLocalIdentifiers: [originalAsset.id], options: nil
                )
                if let sourceAsset = sourceResult.firstObject,
                   let newPlaceholder = request.placeholderForCreatedAsset {
                    placeholderID = newPlaceholder.localIdentifier
                    let albumFetch = PHAssetCollection.fetchAssetCollectionsContaining(
                        sourceAsset, with: .album, options: nil
                    )
                    albumFetch.enumerateObjects { collection, _, _ in
                        guard let albumRequest = PHAssetCollectionChangeRequest(for: collection) else { return }
                        albumRequest.addAssets([newPlaceholder] as NSArray)
                    }
                }
            }, completionHandler: { success, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }

        return placeholderID ?? ""
    }

    // MARK: - Private helpers

    private func createExportSession(for phAsset: PHAsset) async throws -> AVAssetExportSession {
        try await withCheckedThrowingContinuation { cont in
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            PHImageManager.default().requestExportSession(forVideo: phAsset, options: opts, exportPreset: AVAssetExportPresetHEVCHighestQuality) { session, info in
                if let err = info?[PHImageErrorKey] as? Error {
                    cont.resume(throwing: err); return
                }
                guard let session = session else {
                    cont.resume(throwing: ConversionError.exportSessionCreationFailed); return
                }
                cont.resume(returning: session)
            }
        }
    }

    private func buildVideoComposition(
        asset: AVAsset,
        targetResolution: CGSize,
        targetFPS: Double
    ) async throws -> AVVideoComposition? {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else { throw ConversionError.noVideoTrack }

        let duration       = try await asset.load(.duration)
        let naturalSize    = try await videoTrack.load(.naturalSize)
        let preferredTx    = try await videoTrack.load(.preferredTransform)

        var compConfig = AVVideoComposition.Configuration()
        compConfig.frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS.rounded()))
        compConfig.renderSize    = targetResolution

        var instConfig = AVVideoCompositionInstruction.Configuration()
        instConfig.timeRange = CMTimeRange(start: .zero, duration: duration)

        var layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: videoTrack)

        // Scale + apply the preferred transform so portrait videos render correctly
        let scaleX = targetResolution.width  / naturalSize.width
        let scaleY = targetResolution.height / naturalSize.height
        let scale  = min(scaleX, scaleY)
        let scaled = preferredTx.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        layerConfig.setTransform(scaled, at: .zero)

        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)
        instConfig.layerInstructions = [layerInstruction]
        
        let instruction = AVVideoCompositionInstruction(configuration: instConfig)
        compConfig.instructions = [instruction]
        
        return AVVideoComposition(configuration: compConfig)
    }


    private func checkStorageSpace(estimatedBytes: Int64) throws {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: FileManager.default.temporaryDirectory.path
        ),
        let free = attrs[.systemFreeSize] as? Int64 else { return }
        if free < estimatedBytes { throw ConversionError.insufficientStorage }
    }
}
