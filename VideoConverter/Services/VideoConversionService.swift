// VideoConversionService.swift
// VideoConverter

import Foundation
import AVFoundation
import Photos
import CoreLocation
import UIKit
import VideoToolbox

// MARK: - VideoConversionService

final class VideoConversionService {

    static let shared = VideoConversionService()
    private init() {}

    // MARK: - Conversion

    func convert(
        job: ConversionJob,
        progressHandler: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {
        let thermal = ProcessInfo.processInfo.thermalState
        guard thermal != .serious && thermal != .critical else {
            throw ConversionError.exportFailed("Device is too hot. Please wait and try again.")
        }

        let estimated = MetadataService.estimatedOutputBytes(
            sourceBytes: job.sourceAsset.fileSize,
            sourceResolution: job.sourceAsset.resolution,
            sourceFPS: job.sourceAsset.frameRate,
            targetResolution: job.targetResolution,
            targetFPS: job.targetFrameRate
        )
        try VideoConversionUtils.checkStorageSpace(estimatedBytes: max(estimated * 2, 50_000_000))

        let customFilename = job.outputFilename
        let tempFileName = customFilename
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(tempFileName)

        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }

        ConversionLogger.debug("Temp file path: \(tempURL.path)")
        ConversionLogger.debug("Temp dir contents before: \(String(describing: try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)))")

        guard let phAsset = job.sourceAsset.phAsset else {
            throw ConversionError.assetNotFound
        }
        
        try await performExport(
            from: phAsset,
            to: tempURL,
            job: job,
            progressHandler: progressHandler
        )

        return tempURL
    }

    // MARK: - Save to library

    @discardableResult
    func saveToPhotoLibrary(url: URL, originalAsset: VideoAsset, customFilename: String? = nil) async throws -> String {
        ConversionLogger.debug("Attempting to save file at: \(url.path)")
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            let error = ConversionError.exportFailed("Converted file not found at \(url.path)")
            ConversionLogger.debug(error.errorDescription ?? "")
            throw error
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attrs[.size] as? Int64, fileSize > 0 else {
            let error = ConversionError.exportFailed("Converted file is empty")
            ConversionLogger.debug(error.errorDescription ?? "")
            throw error
        }
        ConversionLogger.debug("File size: \(fileSize) bytes")

        var placeholderID: String?

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let opts = PHAssetResourceCreationOptions()
                let filename = customFilename ?? {
                    let stem = (originalAsset.filename as NSString).deletingPathExtension
                    let ext = (originalAsset.filename as NSString).pathExtension
                    return "\(stem).\(ext.isEmpty ? "mov" : ext)"
                }()
                opts.originalFilename = filename

                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: opts)
                request.creationDate = originalAsset.creationDate
                request.isFavorite   = originalAsset.isFavorite
                if let coord = originalAsset.locationCoordinate {
                    request.location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                }

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
                if let error {
                    ConversionLogger.error("Save error: \(error.localizedDescription) (code: \((error as NSError).code))")
                    cont.resume(throwing: error)
                } else {
                    ConversionLogger.debug("Save succeeded")
                    cont.resume()
                }
            })
        }

        return placeholderID ?? ""
    }

    // MARK: - Export

    private func performExport(
        from phAsset: PHAsset,
        to outputURL: URL,
        job: ConversionJob,
        progressHandler: @escaping @MainActor (Double) -> Void
    ) async throws {
        let avAsset = try await loadAVAsset(from: phAsset)
        let duration = try await avAsset.load(.duration)
        let durationSeconds = duration.seconds

        let inputBitrate = VideoConversionUtils.calculateBitrate(fileSize: job.sourceAsset.fileSize, duration: durationSeconds)
        let targetBitrate: Int
        if job.keepOriginalBitrate {
            targetBitrate = inputBitrate
        } else {
            targetBitrate = VideoConversionUtils.calculateTargetBitrate(
                inputBitrate: inputBitrate,
                targetBitrate: job.targetBitrate,
                compressionRatio: 0.65
            )
        }

        VideoConversionUtils.printInputStats(asset: avAsset, sourceAsset: job.sourceAsset, inputBitrate: inputBitrate, targetBitrate: targetBitrate)

        let needsDownscale = job.targetResolution.width < job.sourceAsset.resolution.width - 1 ||
                             job.targetResolution.height < job.sourceAsset.resolution.height - 1

        if needsDownscale {
            try await exportWithAVAssetWriter(
                asset: avAsset,
                to: outputURL,
                targetResolution: job.targetResolution,
                targetFPS: job.targetFrameRate,
                targetBitrate: targetBitrate,
                duration: durationSeconds,
                progressHandler: progressHandler,
                removeHDR: job.removeHDR
            )
        } else {
            try await exportWithAVAssetWriter(
                asset: avAsset,
                to: outputURL,
                targetResolution: job.sourceAsset.resolution,
                targetFPS: job.targetFrameRate,
                targetBitrate: targetBitrate,
                duration: durationSeconds,
                progressHandler: progressHandler,
                removeHDR: job.removeHDR
            )
        }

        VideoConversionUtils.printOutputStats(url: outputURL)
    }

    private func exportWithAVAssetWriter(
        asset: AVAsset,
        to outputURL: URL,
        targetResolution: CGSize,
        targetFPS: Double,
        targetBitrate: Int,
        duration: Double,
        progressHandler: @escaping @MainActor (Double) -> Void,
        removeHDR: Bool = false
    ) async throws {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw ConversionError.noVideoTrack
        }

        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let sourceFrameRate = Double(try await sourceVideoTrack.load(.nominalFrameRate))

        // fpsIsOriginal is true when the difference is negligible (< 0.5 fps).
        let fpsIsOriginal = abs(targetFPS - sourceFrameRate) < 0.5

        // frameSkipInterval > 1 only when we are reducing FPS.
        // e.g. 60fps -> 30fps gives interval = 2.0 (keep 1 frame, skip 1).
        let frameSkipInterval: Double = (!fpsIsOriginal && sourceFrameRate > targetFPS)
            ? sourceFrameRate / targetFPS
            : 1.0

        if !fpsIsOriginal {
            ConversionLogger.debug("Frame rate conversion: \(Int(sourceFrameRate))fps -> \(Int(targetFPS))fps (skip interval: \(frameSkipInterval))")
        }

        let isPortrait = abs(preferredTransform.b) == 1 && abs(preferredTransform.c) == 0
        let effectiveWidth = isPortrait ? naturalSize.height : naturalSize.width
        let effectiveHeight = isPortrait ? naturalSize.width : naturalSize.height

        let scaleX = targetResolution.width / effectiveWidth
        let scaleY = targetResolution.height / effectiveHeight
        let scale = min(scaleX, scaleY, 1.0)

        let outputWidth = Int(effectiveWidth * scale)
        let outputHeight = Int(effectiveHeight * scale)

        var transform = preferredTransform
        if isPortrait {
            if preferredTransform.b == 1 {
                transform = CGAffineTransform(translationX: 0, y: -naturalSize.height)
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(rotationAngle: .pi / 2))
            } else {
                transform = CGAffineTransform(translationX: -naturalSize.width, y: 0)
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(rotationAngle: -.pi / 2))
            }
        } else {
            transform = preferredTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        }

        let reader = try AVAssetReader(asset: asset)

        // FIX: When preserving HDR, use a 10-bit pixel format so the decoder
        // does NOT tone-map or strip HDR/Dolby Vision metadata on read.
        // kCVPixelFormatType_32BGRA is 8-bit SDR — using it unconditionally
        // was destroying HDR data even when removeHDR = false.
        let videoReaderSettings: [String: Any]
        let pixelBufferAttributes: [String: Any]

        if removeHDR {
            // SDR path: 8-bit 4:2:0, tone-mapping happens implicitly on decode.
            videoReaderSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            pixelBufferAttributes = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: outputWidth,
                kCVPixelBufferHeightKey as String: outputHeight
            ]
        } else {
            // HDR-preserving path: 10-bit 4:2:0 keeps HLG, PQ/HDR10, and the
            // Dolby Vision base layer intact through the transcode pipeline.
            videoReaderSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            pixelBufferAttributes = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: outputWidth,
                kCVPixelBufferHeightKey as String: outputHeight
            ]
        }

        let videoOutput = AVAssetReaderTrackOutput(track: sourceVideoTrack, outputSettings: videoReaderSettings)
        videoOutput.alwaysCopiesSampleData = false

        if reader.canAdd(videoOutput) {
            reader.add(videoOutput)
        } else {
            throw ConversionError.assetLoadFailed
        }

        var audioOutput: AVAssetReaderTrackOutput?
        if let sourceAudioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            let audioReaderSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            if reader.canAdd(AVAssetReaderTrackOutput(track: sourceAudioTrack, outputSettings: audioReaderSettings)) {
                let output = AVAssetReaderTrackOutput(track: sourceAudioTrack, outputSettings: audioReaderSettings)
                output.alwaysCopiesSampleData = false
                reader.add(output)
                audioOutput = output
            }
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        ConversionLogger.debug("Writer created at: \(outputURL.path)")

        // Copy all available metadata from source to output
        writer.metadata = try await MetadataService.extractAllMetadata(from: asset)

        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: targetBitrate,
        ]
        if !fpsIsOriginal {
            compressionProps[AVVideoExpectedSourceFrameRateKey] = targetFPS
        }
        // FIX: Use Main10 profile when preserving HDR so the encoder accepts
        // 10-bit pixel buffers. Main profile (8-bit) would reject them and
        // silently fall back to SDR or fail at runtime.
        #if !targetEnvironment(simulator)
        compressionProps[AVVideoProfileLevelKey] = removeHDR
            ? kVTProfileLevel_HEVC_Main_AutoLevel
            : kVTProfileLevel_HEVC_Main10_AutoLevel
        #endif

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: outputWidth,
            AVVideoHeightKey: outputHeight,
            AVVideoCompressionPropertiesKey: compressionProps
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform
        
        // Copy track-level metadata for the video track (includes lens info)
        videoInput.metadata = try await MetadataService.extractTrackMetadata(from: asset)

        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }

        var videoComposition: AVMutableVideoComposition?
        if removeHDR {
            compressionProps[kVTCompressionPropertyKey_PreserveDynamicHDRMetadata as String] = false

            videoComposition = AVMutableVideoComposition(asset: asset) { request in
                request.finish(with: request.sourceImage, context: nil)
            }
            videoComposition?.renderSize = CGSize(width: outputWidth, height: outputHeight)
            videoComposition?.frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            videoComposition?.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            videoComposition?.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
            videoComposition?.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        }

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = fpsIsOriginal
            ? Int(duration * sourceFrameRate)
            : Int(duration * targetFPS)

        // framesRead counts every source frame decoded.
        // framesWritten counts every frame actually appended to the output.
        // frameAccumulator tracks the fractional position so drops are spread evenly
        // across the video (avoids judder from naive modulo skipping).
        var framesWritten: Int64 = 0
        var framesRead: Int64 = 0
        var frameAccumulator: Double = 0.0

        final class TaskManager: @unchecked Sendable {
            var taskID: UIBackgroundTaskIdentifier = .invalid
        }
        let manager = TaskManager()
        await MainActor.run {
            manager.taskID = UIApplication.shared.beginBackgroundTask(withName: "HEVCConvert") { [weak manager] in
                if let id = manager?.taskID, id != .invalid {
                    UIApplication.shared.endBackgroundTask(id)
                }
            }
        }

        let videoQueue = DispatchQueue(label: "com.videoconverter.video.write")
        let audioQueue = DispatchQueue(label: "com.videoconverter.audio.write")

        let videoGroup = DispatchGroup()
        let audioGroup = DispatchGroup()

        var videoCompleted = false
        var audioCompleted = audioInput == nil

        videoGroup.enter()
        videoInput.requestMediaDataWhenReady(on: videoQueue) {
            while videoInput.isReadyForMoreMediaData {
                autoreleasepool {
                    if let sourceSampleBuffer = videoOutput.copyNextSampleBuffer() {
                        framesRead += 1

                        // Accumulator-based frame skipping for even cadence.
                        if frameSkipInterval > 1.0 {
                            frameAccumulator += 1.0
                            if frameAccumulator < frameSkipInterval {
                                return // skip this source frame
                            }
                            frameAccumulator -= frameSkipInterval
                        }

                        // Assign new sequential timestamps when doing FPS conversion.
                        let presentationTime: CMTime
                        if fpsIsOriginal {
                            presentationTime = CMSampleBufferGetPresentationTimeStamp(sourceSampleBuffer)
                        } else {
                            presentationTime = CMTime(value: framesWritten, timescale: Int32(targetFPS))
                        }

                        // Get camera intrinsic matrix from source sample buffer attachment
                        let cameraIntrinsicMatrix = CMGetAttachment(
                            sourceSampleBuffer,
                            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                            attachmentModeOut: nil
                        )

                        if let pixelBuffer = CMSampleBufferGetImageBuffer(sourceSampleBuffer) {
                            if removeHDR {
                                // SDR path: render through CIContext into a fresh 8-bit BGRA buffer.
                                // This intentionally tone-maps and strips HDR metadata.
                                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                                let context = CIContext()

                                var renderedBuffer: CVPixelBuffer?
                                let status = CVPixelBufferCreate(
                                    kCFAllocatorDefault,
                                    outputWidth,
                                    outputHeight,
                                    kCVPixelFormatType_32BGRA,
                                    pixelBufferAttributes as CFDictionary,
                                    &renderedBuffer
                                )

                                if status == kCVReturnSuccess, let buffer = renderedBuffer {
                                    context.render(ciImage, to: buffer)

                                    if let matrix = cameraIntrinsicMatrix {
                                        CMSetAttachment(
                                            buffer,
                                            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                            value: matrix,
                                            attachmentMode: kCMAttachmentMode_ShouldPropagate
                                        )
                                    }

                                    if pixelBufferAdaptor.append(buffer, withPresentationTime: presentationTime) {
                                        framesWritten += 1
                                        let progress = totalFrames > 0 ? min(Double(framesWritten) / Double(totalFrames), 1.0) : 0
                                        if Int(framesWritten) % max(1, totalFrames / 10) == 0 {
                                            Task { @MainActor in
                                                progressHandler(progress)
                                            }
                                        }
                                    }
                                }
                            } else {
                                // FIX: HDR-preserving path — pass the decoded 10-bit pixel buffer
                                // directly to the adaptor without going through CIContext/BGRA.
                                // CIContext always outputs BGRA (8-bit SDR), so routing HDR frames
                                // through it was silently destroying all HDR/Dolby Vision data even
                                // when removeHDR was false. Direct passthrough keeps the 10-bit
                                // values and transfer function (HLG/PQ) intact.
                                if let matrix = cameraIntrinsicMatrix {
                                    CMSetAttachment(
                                        pixelBuffer,
                                        key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                        value: matrix,
                                        attachmentMode: kCMAttachmentMode_ShouldPropagate
                                    )
                                }

                                if pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                                    framesWritten += 1
                                    let progress = totalFrames > 0 ? min(Double(framesWritten) / Double(totalFrames), 1.0) : 0
                                    if Int(framesWritten) % max(1, totalFrames / 10) == 0 {
                                        Task { @MainActor in
                                            progressHandler(progress)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        videoInput.markAsFinished()
                        videoCompleted = true
                        videoGroup.leave()
                    }
                }
            }
        }

        if let audioOutput = audioOutput, let audioInput = audioInput {
            audioGroup.enter()
            audioInput.requestMediaDataWhenReady(on: audioQueue) {
                while audioInput.isReadyForMoreMediaData {
                    if let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                        audioInput.append(sampleBuffer)
                    } else {
                        audioInput.markAsFinished()
                        audioCompleted = true
                        audioGroup.leave()
                        break
                    }
                }
            }
        } else {
            audioCompleted = true
        }

        while !videoCompleted || !audioCompleted {
            if videoCompleted && audioCompleted { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        if let error = reader.error {
            ConversionLogger.debug("Reader error: \(error.localizedDescription)")
        }

        await MainActor.run {
            UIApplication.shared.endBackgroundTask(manager.taskID)
        }

        if videoCompleted && audioCompleted {
            await writer.finishWriting()
            ConversionLogger.debug("Writer status: \(writer.status.rawValue)")
            
            switch writer.status {
            case .completed:
                ConversionLogger.debug("Writer completed successfully")
                Task { @MainActor in
                    progressHandler(1.0)
                }
            case .failed:
                let error = writer.error
                let nsError = error as NSError?
                ConversionLogger.error("Writer failed: \(error?.localizedDescription ?? "unknown")")
                ConversionLogger.error("Error domain: \(nsError?.domain ?? "unknown")")
                ConversionLogger.error("Error code: \(nsError?.code ?? -1)")
                ConversionLogger.error("Error userInfo: \(nsError?.userInfo ?? [:])")
                throw ConversionError.exportFailed(error?.localizedDescription ?? "Unknown writer error")
            case .cancelled:
                ConversionLogger.debug("Writer cancelled")
                throw ConversionError.exportFailed("Writer was cancelled")
            case .writing, .unknown:
                ConversionLogger.debug("Writer unexpected state: \(writer.status.rawValue)")
                throw ConversionError.exportFailed("Writer unexpected state: \(writer.status.rawValue)")
            @unknown default:
                ConversionLogger.debug("Writer unknown state: \(writer.status.rawValue)")
                throw ConversionError.exportFailed("Unknown writer state: \(writer.status.rawValue)")
            }
        } else {
            throw ConversionError.exportFailed("Video/Audio processing did not complete")
        }
    }

    private func loadAVAsset(from phAsset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { cont in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    ConversionLogger.error("Load asset error: \(error.localizedDescription)")
                    cont.resume(throwing: error)
                } else if let asset {
                    cont.resume(returning: asset)
                } else {
                    cont.resume(throwing: ConversionError.assetLoadFailed)
                }
            }
        }
    }
}
