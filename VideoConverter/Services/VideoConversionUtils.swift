// VideoConversionUtils.swift
// VideoConverter

import Foundation
import AVFoundation
import Photos
import CoreLocation

enum ConversionError: LocalizedError {
    case assetLoadFailed
    case assetNotFound
    case exportSessionCreationFailed
    case exportFailed(String)
    case noVideoTrack
    case insufficientStorage
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetLoadFailed:              return "Could not load the video from your library."
        case .assetNotFound:                return "The video asset was not found in your library."
        case .exportSessionCreationFailed:  return "Could not create an export session."
        case .exportFailed(let reason):     return "Export failed: \(reason)"
        case .noVideoTrack:                return "The video has no video track."
        case .insufficientStorage:          return "Not enough storage space to complete the conversion."
        case .encodingFailed(let reason):   return "Encoding failed: \(reason)"
        }
    }
}

enum ConversionLogger {
    private static let prefix = "[VideoConversionService]"

    static func debug(_ message: String) {
        print("\(prefix) \(message)")
    }

    static func stats(_ message: String) {
        print(message)
    }

    static func error(_ message: String) {
        print("\(prefix) ERROR: \(message)")
    }
}

enum VideoConversionUtils {

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    static func formatBitrate(_ bitsPerSecond: Double) -> String {
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Mbps", bitsPerSecond / 1_000_000)
        } else if bitsPerSecond >= 1_000 {
            return String(format: "%.0f kbps", bitsPerSecond / 1_000)
        }
        return String(format: "%.0f bps", bitsPerSecond)
    }

    static func getCodecName(from track: AVAssetTrack) async -> String {
        guard let formatDescriptions = try? await track.load(.formatDescriptions),
              let desc = formatDescriptions.first else { return "Unknown" }

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

    static func calculateBitrate(fileSize: Int64, duration: Double) -> Int {
        guard duration > 0 else { return 2_000_000 }
        let bitsPerSecond = Double(fileSize * 8) / duration
        return max(Int(bitsPerSecond), 500_000)
    }

    static func calculateTargetBitrate(inputBitrate: Int, targetBitrate: Int?, compressionRatio: Double) -> Int {
        if let explicit = targetBitrate {
            return explicit
        }
        let target = Double(inputBitrate) * compressionRatio
        return max(Int(target), 100_000)
    }

    static func checkStorageSpace(estimatedBytes: Int64) throws {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: FileManager.default.temporaryDirectory.path
        ),
        let free = attrs[.systemFreeSize] as? Int64 else { return }
        if free < estimatedBytes { throw ConversionError.insufficientStorage }
    }

    static func printInputStats(asset: AVAsset, sourceAsset: VideoAsset, inputBitrate: Int, targetBitrate: Int) {
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

                let percent = inputBitrate > 0 ? (Double(targetBitrate) / Double(inputBitrate) * 100) : 0

                ConversionLogger.stats("""
                    [VideoConversionService] ═══ INPUT ═══
                    Codec: \(codec)
                    Resolution: \(Int(naturalSize.width))×\(Int(naturalSize.height))
                    FPS: \(String(format: "%.2f", frameRate))
                    Duration: \(formatDuration(durationSecs))
                    File Size: \(formatBytes(sourceAsset.fileSize))
                    Bitrate: \(formatBitrate(bitrate))
                    Target Bitrate: \(formatBitrate(Double(targetBitrate))) (\(String(format: "%.0f", percent))% of input)
                    ═══════════════════════════════════
                    """)
            } catch {
                ConversionLogger.debug("Failed to load input stats: \(error)")
            }
        }
    }

    static func printOutputStats(url: URL) {
        Task {
            do {
                let asset = AVURLAsset(url: url)
                let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let videoTrack = tracks.first else { return }

                let codec = await getCodecName(from: videoTrack)
                let frameRate = try await videoTrack.load(.nominalFrameRate)
                let naturalSize = try await videoTrack.load(.naturalSize)
                let duration = try await asset.load(.duration)

                let durationSecs = duration.seconds
                let bitrate = durationSecs > 0 ? Double(fileSize * 8) / durationSecs : 0

                ConversionLogger.stats("""
                    [VideoConversionService] ═══ OUTPUT ═══
                    Codec: \(codec)
                    Resolution: \(Int(naturalSize.width))×\(Int(naturalSize.height))
                    FPS: \(String(format: "%.2f", frameRate))
                    Duration: \(formatDuration(durationSecs))
                    File Size: \(formatBytes(fileSize))
                    Bitrate: \(formatBitrate(bitrate))
                    ═══════════════════════════════════
                    """)
            } catch {
                ConversionLogger.debug("Failed to load output stats: \(error)")
            }
        }
    }
}
