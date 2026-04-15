// VideoConversionService.swift
// VideoConverter

import Foundation
import AVFoundation
import Photos
import CoreLocation
import UIKit
import VideoToolbox

// MARK: - Errors

enum ConversionError: LocalizedError {
    case assetLoadFailed
    case exportSessionCreationFailed
    case exportFailed(String)
    case noVideoTrack
    case insufficientStorage
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetLoadFailed:              return "Could not load the video from your library."
        case .exportSessionCreationFailed:  return "Could not create an export session."
        case .exportFailed(let reason):     return "Export failed: \(reason)"
        case .noVideoTrack:                 return "The video has no video track."
        case .insufficientStorage:          return "Not enough storage space to complete the conversion."
        case .encodingFailed(let reason):   return "Encoding failed: \(reason)"
        }
    }
}

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
        try checkStorageSpace(estimatedBytes: max(estimated * 2, 50_000_000))

        let tempFileName = "HEVC_\(ProcessInfo.processInfo.processIdentifier)_\(Date().timeIntervalSince1970)_\(UUID().uuidString).mov"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(tempFileName)

        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }

        print("[VideoConversionService] Temp file path: \(tempURL.path)")
        print("[VideoConversionService] Temp dir contents before: \(String(describing: try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)))")

        try await performExport(
            from: job.sourceAsset.phAsset,
            to: tempURL,
            job: job,
            progressHandler: progressHandler
        )

        return tempURL
    }

    // MARK: - Save to library

    @discardableResult
    func saveToPhotoLibrary(url: URL, originalAsset: VideoAsset) async throws -> String {
        print("[VideoConversionService] Attempting to save file at: \(url.path)")
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            let error = ConversionError.exportFailed("Converted file not found at \(url.path)")
            print("[VideoConversionService] \(error.errorDescription ?? "")")
            throw error
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attrs[.size] as? Int64, fileSize > 0 else {
            let error = ConversionError.exportFailed("Converted file is empty")
            print("[VideoConversionService] \(error.errorDescription ?? "")")
            throw error
        }
        print("[VideoConversionService] File size: \(fileSize) bytes")

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
                    print("[VideoConversionService] Save error: \(error.localizedDescription) (code: \((error as NSError).code))")
                    cont.resume(throwing: error)
                } else {
                    print("[VideoConversionService] Save succeeded")
                    cont.resume()
                }
            })
        }

        return placeholderID ?? ""
    }

    // MARK: - Private helpers

    private func checkStorageSpace(estimatedBytes: Int64) throws {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: FileManager.default.temporaryDirectory.path
        ),
        let free = attrs[.systemFreeSize] as? Int64 else { return }
        if free < estimatedBytes { throw ConversionError.insufficientStorage }
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

        let inputBitrate = calculateBitrate(fileSize: job.sourceAsset.fileSize, duration: durationSeconds)
        let targetBitrate = calculateTargetBitrate(
            inputBitrate: inputBitrate,
            targetBitrate: job.targetBitrate,
            compressionRatio: 0.65
        )

        printStats(input: avAsset, sourceAsset: job.sourceAsset, label: "INPUT", inputBitrate: inputBitrate, targetBitrate: targetBitrate)

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
                progressHandler: progressHandler
            )
        } else {
            try await exportWithAVAssetWriter(
                asset: avAsset,
                to: outputURL,
                targetResolution: job.sourceAsset.resolution,
                targetFPS: job.targetFrameRate,
                targetBitrate: targetBitrate,
                duration: durationSeconds,
                progressHandler: progressHandler
            )
        }

        printStats(url: outputURL, label: "OUTPUT")
    }

    private func calculateBitrate(fileSize: Int64, duration: Double) -> Int {
        guard duration > 0 else { return 2_000_000 }
        let bitsPerSecond = Double(fileSize * 8) / duration
        return max(Int(bitsPerSecond), 500_000)
    }

    private func calculateTargetBitrate(inputBitrate: Int, targetBitrate: Int?, compressionRatio: Double) -> Int {
        if let explicit = targetBitrate {
            return explicit
        }
        let target = Double(inputBitrate) * compressionRatio
        return max(Int(target), 100_000)
    }

    private func exportWithAVAssetWriter(
        asset: AVAsset,
        to outputURL: URL,
        targetResolution: CGSize,
        targetFPS: Double,
        targetBitrate: Int,
        duration: Double,
        progressHandler: @escaping @MainActor (Double) -> Void
    ) async throws {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw ConversionError.noVideoTrack
        }

        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let sourceFrameRate = Double(try await sourceVideoTrack.load(.nominalFrameRate))
        let fpsIsOriginal = abs(targetFPS - sourceFrameRate) < 0.5

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

        let videoReaderSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

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
        print("[VideoConversionService] Writer created at: \(outputURL.path)")

        let sourceMetadata = try await asset.load(.metadata)
        writer.metadata = sourceMetadata

        let commonMetadata = try await asset.load(.commonMetadata)
        if let cameraMake = commonMetadata.first(where: { $0.commonKey?.rawValue == "make" }) as? AVMetadataItem,
           let cameraModel = commonMetadata.first(where: { $0.commonKey?.rawValue == "model" }) as? AVMetadataItem {
            writer.metadata.append(cameraMake)
            writer.metadata.append(cameraModel)
        }

        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: targetBitrate,
        ]
        if !fpsIsOriginal {
            compressionProps[AVVideoExpectedSourceFrameRateKey] = targetFPS
        }
        #if !targetEnvironment(simulator)
        compressionProps[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel
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

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outputWidth,
            kCVPixelBufferHeightKey as String: outputHeight
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
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

        let frameSkipInterval = !fpsIsOriginal && sourceFrameRate > targetFPS ? sourceFrameRate / targetFPS : 1
        let totalFrames = fpsIsOriginal
            ? Int(duration * sourceFrameRate)
            : Int(duration * targetFPS)
        var framesWritten: Int64 = 0
        var framesRead: Int64 = 0

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
            let adaptor = pixelBufferAdaptor

            while videoInput.isReadyForMoreMediaData {
                autoreleasepool {
                    if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                        framesRead += 1

                        let shouldSkip = frameSkipInterval > 1 && Int(framesRead) % Int(frameSkipInterval) != 0
                        if shouldSkip {
                            return
                        }

                        let presentationTime: CMTime
                        if fpsIsOriginal {
                            presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        } else {
                            presentationTime = CMTime(value: framesWritten, timescale: Int32(targetFPS))
                        }

                        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
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

                                if adaptor.append(buffer, withPresentationTime: presentationTime) {
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
            print("[VideoConversionService] Reader error: \(error.localizedDescription)")
        }

        await MainActor.run {
            UIApplication.shared.endBackgroundTask(manager.taskID)
        }

        if videoCompleted && audioCompleted {
            await writer.finishWriting()
            print("[VideoConversionService] Writer status: \(writer.status.rawValue)")
            
            switch writer.status {
            case .completed:
                print("[VideoConversionService] Writer completed successfully")
                Task { @MainActor in
                    progressHandler(1.0)
                }
            case .failed:
                let error = writer.error
                let nsError = error as NSError?
                print("[VideoConversionService] Writer failed: \(error?.localizedDescription ?? "unknown")")
                print("[VideoConversionService] Error domain: \(nsError?.domain ?? "unknown")")
                print("[VideoConversionService] Error code: \(nsError?.code ?? -1)")
                print("[VideoConversionService] Error userInfo: \(nsError?.userInfo ?? [:])")
                throw ConversionError.exportFailed(error?.localizedDescription ?? "Unknown writer error")
            case .cancelled:
                print("[VideoConversionService] Writer cancelled")
                throw ConversionError.exportFailed("Writer was cancelled")
            case .writing, .unknown:
                print("[VideoConversionService] Writer unexpected state: \(writer.status.rawValue)")
                throw ConversionError.exportFailed("Writer unexpected state: \(writer.status.rawValue)")
            @unknown default:
                print("[VideoConversionService] Writer unknown state: \(writer.status.rawValue)")
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
                    print("[VideoConversionService] Load asset error: \(error.localizedDescription)")
                    cont.resume(throwing: error)
                } else if let asset {
                    cont.resume(returning: asset)
                } else {
                    cont.resume(throwing: ConversionError.assetLoadFailed)
                }
            }
        }
    }

    // MARK: - Stats Logging

    private func printStats(input asset: AVAsset, sourceAsset: VideoAsset, label: String, inputBitrate: Int, targetBitrate: Int) {
        Task {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let videoTrack = tracks.first else { return }

                let codec = await getCodecName(from: videoTrack)
                let frameRate = try await videoTrack.load(.nominalFrameRate)
                let naturalSize = try await videoTrack.load(.naturalSize)
                let duration = try await asset.load(.duration)

                let durationSecs = duration.seconds
                let bitrate = durationSecs > 0 ? Double(sourceAsset.fileSize * 8) / durationSecs : 0

                print("""
                    [VideoConversionService] ═══ \(label) ═══
                    Codec: \(codec)
                    Resolution: \(Int(naturalSize.width))×\(Int(naturalSize.height))
                    FPS: \(String(format: "%.2f", frameRate))
                    Duration: \(formatDuration(durationSecs))
                    File Size: \(formatBytes(sourceAsset.fileSize))
                    Bitrate: \(formatBitrate(bitrate))
                    Target Bitrate: \(formatBitrate(Double(targetBitrate))) (65% of input)
                    ═══════════════════════════════════
                    """)
            } catch {
                print("[VideoConversionService] Failed to load input stats: \(error)")
            }
        }
    }

    private func printStats(url: URL, label: String) {
        let asset = AVURLAsset(url: url)
        Task {
            do {
                let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let videoTrack = tracks.first else { return }

                let codec = await getCodecName(from: videoTrack)
                let frameRate = try await videoTrack.load(.nominalFrameRate)
                let naturalSize = try await videoTrack.load(.naturalSize)
                let duration = try await asset.load(.duration)

                let durationSecs = duration.seconds
                let bitrate = durationSecs > 0 ? Double(fileSize * 8) / durationSecs : 0

                print("""
                    [VideoConversionService] ═══ \(label) ═══
                    Codec: \(codec)
                    Resolution: \(Int(naturalSize.width))×\(Int(naturalSize.height))
                    FPS: \(String(format: "%.2f", frameRate))
                    Duration: \(formatDuration(durationSecs))
                    File Size: \(formatBytes(fileSize))
                    Bitrate: \(formatBitrate(bitrate))
                    ═══════════════════════════════════
                    """)
            } catch {
                print("[VideoConversionService] Failed to load output stats: \(error)")
            }
        }
    }

    private func getCodecName(from track: AVAssetTrack) async -> String {
        let formatDescriptions = try? await track.load(.formatDescriptions)
        guard let desc = formatDescriptions?.first else { return "Unknown" }

        let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
        switch mediaSubType {
        case kCMVideoCodecType_H264:           return "H.264"
        case kCMVideoCodecType_HEVC:          return "HEVC"
        case kCMVideoCodecType_MPEG4Video:    return "MPEG-4"
        case kCMVideoCodecType_AppleProRes422: return "ProRes 422"
        case kCMVideoCodecType_AppleProRes4444: return "ProRes 4444"
        default:
            let bytes: [UInt8] = [
                UInt8((mediaSubType >> 24) & 0xFF),
                UInt8((mediaSubType >> 16) & 0xFF),
                UInt8((mediaSubType >>  8) & 0xFF),
                UInt8((mediaSubType      ) & 0xFF),
            ]
            return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
    
    private func formatBitrate(_ bitsPerSecond: Double) -> String {
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Mbps", bitsPerSecond / 1_000_000)
        } else if bitsPerSecond >= 1_000 {
            return String(format: "%.0f kbps", bitsPerSecond / 1_000)
        }
        return String(format: "%.0f bps", bitsPerSecond)
    }
}
