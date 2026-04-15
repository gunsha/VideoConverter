// VideoAsset.swift
// VideoConverter

import Foundation
import Photos
import CoreLocation

/// A non-HEVC video found in the user's photo library.
struct VideoAsset: Identifiable, Hashable, Sendable {
    let id: String                          // PHAsset.localIdentifier
    let phAsset: PHAsset
    let filename: String
    let fileSize: Int64
    let duration: TimeInterval
    let creationDate: Date?
    let modificationDate: Date?
    let resolution: CGSize
    let frameRate: Double
    let codec: String
    let locationCoordinate: CLLocationCoordinate2D?
    let isFavorite: Bool

    static func == (lhs: VideoAsset, rhs: VideoAsset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Computed display helpers
extension VideoAsset {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDuration: String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    var resolutionLabel: String {
        "\(Int(resolution.width))×\(Int(resolution.height))"
    }

    var frameRateLabel: String {
        let fps = frameRate.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(frameRate))fps"
            : String(format: "%.1ffps", frameRate)
        return fps
    }

    /// Available downscale resolution options (≤ original), standard steps.
    var resolutionOptions: [CGSize] {
        let standards: [CGSize] = [
            CGSize(width: 3840, height: 2160),
            CGSize(width: 1920, height: 1080),
            CGSize(width: 1280, height: 720),
            CGSize(width: 960,  height: 540),
        ]
        return standards.filter { $0.width <= resolution.width && $0.height <= resolution.height }
    }

    /// Available FPS options including original.
    var frameRateOptions: [Double] {
        var options: [Double] = [60, 30, 25, 24]
        if !options.contains(frameRate) {
            options.append(frameRate)
        }
        return options.sorted()
    }
}
