// MetadataService.swift
// VideoConverter

import Foundation
import AVFoundation
import CoreMedia

/// Pure helpers for reading metadata and estimating output sizes.
struct MetadataService {

    // MARK: - Size estimation

    /// Estimates the HEVC output file size.
    /// HEVC is ~45 % of equivalent H.264 at the same resolution/fps.
    static func estimatedOutputBytes(
        sourceBytes: Int64,
        sourceResolution: CGSize,
        sourceFPS: Double,
        targetResolution: CGSize,
        targetFPS: Double
    ) -> Int64 {
        guard sourceResolution.width > 0, sourceResolution.height > 0,
              sourceFPS > 0, targetFPS > 0 else { return 0 }

        let resolutionRatio = (targetResolution.width * targetResolution.height)
            / (sourceResolution.width * sourceResolution.height)
        let fpsRatio = targetFPS / sourceFPS
        let hevcEfficiency = 0.45

        return Int64(Double(sourceBytes) * resolutionRatio * fpsRatio * hevcEfficiency)
    }

    /// Human-readable formatted string for a byte count.
    static func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Bitrate heuristic

    /// Computes a reasonable HEVC target bitrate (bps) for the given resolution and FPS.
    static func targetBitrate(resolution: CGSize, frameRate: Double) -> Int {
        // ~0.08 bits-per-pixel-per-frame is good quality for HEVC
        let bppf = 0.08
        return max(500_000, Int(resolution.width * resolution.height * frameRate * bppf))
    }

    static func estimateSize(bitrate: Int, durationSeconds: Double) -> Int64 {
        Int64(Double(bitrate) / 8.0 * durationSeconds)
    }

    static func estimateSize(bitrate: Int, frameCount: Int, fps: Double) -> Int64 {
        let duration = Double(frameCount) / fps
        return estimateSize(bitrate: bitrate, durationSeconds: duration)
    }

    // MARK: - Metadata extraction

    /// Known QuickTime camera/lens metadata keys that need special handling
    private static let quickTimeCameraKeys: [String] = [
        "com.apple.quicktime.camera.lens_model",
        "com.apple.quicktime.camera.focal_length.35mm_equivalent",
        "com.apple.quicktime.camera.lens_iris_aperture",
        "com.apple.quicktime.camera.model",
        "com.apple.quicktime.lens.model",
        "com.apple.quicktime.lens.focal_length",
        "com.apple.quicktime.lens.max_aperture",
        "com.apple.quicktime.lens.min_aperture",
        "com.apple.quicktime.camera.iso",
        "com.apple.quicktime.camera.exposure_time",
        "com.apple.quicktime.camera.brightness",
    ]

    private static let quickTimeCameraKeyVariants: [[String]] = [
        ["com.apple.quicktime.camera.lens_model", "com.apple.quicktime.lens.model"],
        ["com.apple.quicktime.camera.focal_length.35mm_equivalent"],
        ["com.apple.quicktime.camera.lens_iris_aperture", "com.apple.quicktime.lens.max_aperture"],
        ["com.apple.quicktime.camera.model"],
        ["com.apple.quicktime.lens.focal_length"],
        ["com.apple.quicktime.camera.iso"],
        ["com.apple.quicktime.camera.exposure_time"],
    ]

    /// Extracts all metadata from an AVAsset and returns it for writing to a new file.
    /// Copies common metadata, QuickTime metadata, and video track metadata.
    /// Re-creates QuickTime camera/lens metadata with proper keySpace and dataType.
    static func extractAllMetadata(from asset: AVAsset) async throws -> [AVMetadataItem] {
        var outputMetadata: [AVMetadataItem] = []
        let existingKeys = NSMutableSet()
        
        // 1. Copy all common metadata
        let commonMetadata = try await asset.load(.commonMetadata)
        for item in commonMetadata {
            outputMetadata.append(item)
            if let key = item.commonKey?.rawValue {
                existingKeys.add(key)
            }
        }
        
        // 2. Copy all QuickTime metadata (avoiding duplicates)
        let sourceMetadata = try await asset.load(.metadata)
        for item in sourceMetadata {
            if let identifier = item.identifier {
                if !outputMetadata.contains(where: { $0.identifier == identifier }) {
                    outputMetadata.append(item)
                    existingKeys.add(identifier.rawValue)
                }
            } else if let key = item.key as? String {
                if !existingKeys.contains(key) {
                    outputMetadata.append(item)
                    existingKeys.add(key)
                }
            } else {
                outputMetadata.append(item)
            }
        }
        
        // 3. Extract and re-create video track metadata with proper formatting
        if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
            let trackMetadata = try await videoTrack.load(.metadata)
            for item in trackMetadata {
                guard let key = item.key as? String else { continue }
                
                if !existingKeys.contains(key) {
                    let keyNeedsRecreation = quickTimeCameraKeys.contains(key) || key.hasPrefix("com.apple.quicktime.lens.")
                    
                    if keyNeedsRecreation {
                        if let recreatedItem = await recreateQuickTimeMetadataItem(from: item) {
                            outputMetadata.append(recreatedItem)
                        } else {
                            outputMetadata.append(item)
                        }
                        
                        for variantGroup in quickTimeCameraKeyVariants {
                            if variantGroup.contains(key) {
                                for variant in variantGroup {
                                    existingKeys.add(variant)
                                }
                            }
                        }
                        existingKeys.add(key)
                    } else {
                        outputMetadata.append(item)
                        existingKeys.add(key)
                    }
                }
            }
        }
        
        return outputMetadata
    }

    /// Recreates a QuickTime metadata item with proper keySpace (mdta) and dataType
    private static func recreateQuickTimeMetadataItem(from original: AVMetadataItem) async -> AVMetadataItem? {
        guard let key = original.key as? String else { return nil }
        
        let keySpace = AVMetadataKeySpace(rawValue: "mdta")
        
        // Determine data type and create appropriate value
        var dataType: String
        var value: (any NSCopying & NSObjectProtocol)?
        
        if let stringValue = try? await original.load(.stringValue) {
            dataType = "com.apple.metadata.datatype.UTF-8"
            value = stringValue as NSString
        } else if let numberValue = try? await original.load(.numberValue) {
            // Check if it's a floating point or integer
            if CFNumberIsFloatType(numberValue) {
                dataType = "com.apple.metadata.datatype.float32"
            } else {
                dataType = "com.apple.metadata.datatype.integer32"
            }
            value = numberValue
        } else if let dataValue = try? await original.load(.dataValue) {
            dataType = "com.apple.metadata.datatype.raw-data"
            value = dataValue as NSData
        } else {
            // Try to infer from the original dataType
            if let originalDataType = original.dataType {
                dataType = originalDataType
                if let anyValue = original.value {
                    value = anyValue as? (any NSCopying & NSObjectProtocol)
                }
            } else {
                return nil
            }
        }
        
        guard let finalValue = value else { return nil }
        
        let item = AVMutableMetadataItem()
        item.key = key as (NSCopying & NSObjectProtocol)
        item.keySpace = keySpace
        item.value = finalValue
        item.dataType = dataType
        
        return item
    }
    
    /// Extracts metadata specifically for track-level (video/audio track).
    /// This includes lens, camera, and other device-specific metadata.
    static func extractTrackMetadata(from asset: AVAsset) async throws -> [AVMetadataItem] {
        var trackMetadata: [AVMetadataItem] = []
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return trackMetadata
        }
        
        let metadata = try await videoTrack.load(.metadata)
        
        for item in metadata {
            // Convert to mutable so we can write it
            if let mutableItem = item.copy() as? AVMetadataItem {
                trackMetadata.append(mutableItem)
            }
        }
        
        return trackMetadata
    }
}
