// EstimatedSizeFooter.swift
// VideoConverter

import SwiftUI

struct EstimatedSizeFooter: View {
    let asset: VideoAsset
    let selectedResolution: CGSize
    let selectedFPS: Double
    let bitratePercent: Double
    let keepOriginalBitrate: Bool

    private var inputBitrate: Int {
        guard asset.duration > 0 else { return 2_000_000 }
        return max(Int(Double(asset.fileSize * 8) / asset.duration), 500_000)
    }

    private var targetBitrate: Int {
        if keepOriginalBitrate {
            return inputBitrate
        }
        return Int(Double(inputBitrate) * (bitratePercent / 100.0))
    }

    private var estimatedBytes: Int64 {
        if keepOriginalBitrate {
            return asset.fileSize
        }

        let adjustedFPS = min(selectedFPS, asset.frameRate)
        let duration = asset.duration * (adjustedFPS / asset.frameRate)

        return VideoConversionUtils.estimatedHEVCFileSize(
            durationSeconds: duration,
            videoBitrate: targetBitrate,
            fps: adjustedFPS,
            resolution: (width: Int(selectedResolution.width), height: Int(selectedResolution.height))
        )
    }

    private var savings: Int {
        guard asset.fileSize > 0, estimatedBytes > 0 else { return 0 }
        let saved = Double(asset.fileSize - estimatedBytes) / Double(asset.fileSize)
        return max(0, Int((saved * 100).rounded()))
    }

    var body: some View {
        HStack {
            Text("Estimated output size")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 8) {
                Text(MetadataService.format(bytes: estimatedBytes))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                SavingsTag(percentage: savings)
            }
        }
    }
}

private struct SavingsTag: View {
    let percentage: Int

    var body: some View {
        Text("~\(percentage)%")
            .font(.caption.weight(.medium))
            .foregroundStyle(percentage >= 30 ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(percentage >= 30 ? Color.green : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 6))
    }
}
