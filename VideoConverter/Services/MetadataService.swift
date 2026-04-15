// MetadataService.swift
// VideoConverter

import Foundation
import AVFoundation

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
}
