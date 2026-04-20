// ConversionSettingsForm.swift
// VideoConverter

import SwiftUI

struct ConversionSettingsForm: View {
    let asset: VideoAsset

    @Binding var selectedResolution: CGSize
    @Binding var selectedFPS: Double
    @Binding var bitratePercent: Double
    @Binding var removeHDR: Bool
    @Binding var keepOriginalBitrate: Bool

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

    private var recommendedBitrateText: String {
        let recommended = VideoConversionUtils.recommendedHEVCBitrate(
            width: Int(selectedResolution.width),
            height: Int(selectedResolution.height),
            fps: selectedFPS
        )
        return formatBitrate(recommended)
    }

    var body: some View {
        VStack(spacing: 16) {
            if asset.isHDR {
                SettingsSection(title: "HDR") {
                    Toggle("Remove HDR", isOn: $removeHDR)
                    Divider()
                    Text("Removes HDR metadata and tone-maps to SDR Rec.709 for better compatibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection(title: "Output Resolution") {
                ForEach(asset.resolutionOptions.indices, id: \.self) { idx in
                    let res = asset.resolutionOptions[idx]
                    ResolutionRow(
                        resolution: res,
                        isSelected: selectedResolution == res,
                        onTap: { withAnimation { selectedResolution = res } }
                    )
                    if idx < asset.resolutionOptions.count - 1 {
                        Divider()
                    }
                }
            }

            SettingsSection(title: "Frame Rate") {
                let fpsOptions = asset.frameRateOptions.filter { $0 <= asset.frameRate }
                ForEach(fpsOptions.indices, id: \.self) { idx in
                    let fps = fpsOptions[idx]
                    FrameRateRow(
                        fps: fps,
                        originalFPS: asset.frameRate,
                        isSelected: abs(selectedFPS - fps) < 0.5,
                        onTap: { withAnimation { selectedFPS = fps } }
                    )
                    if idx < fpsOptions.count - 1 {
                        Divider()
                    }
                }
            }

            SettingsSection(title: "Target Bitrate") {
                Toggle("Keep original bitrate", isOn: $keepOriginalBitrate)
                Divider()

                if !keepOriginalBitrate {
                    BitrateSlider(
                        bitratePercent: $bitratePercent,
                        targetBitrate: targetBitrate,
                        inputBitrate: inputBitrate
                    )
                    Divider()
                }

                BitrateFooter(
                    keepOriginalBitrate: keepOriginalBitrate,
                    recommendedBitrateText: recommendedBitrateText,
                    selectedFPS: selectedFPS,
                    selectedResolution: selectedResolution
                )
            }
        }
    }

    private func formatBitrate(_ bitsPerSecond: Int) -> String {
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitsPerSecond) / 1_000_000)
        } else if bitsPerSecond >= 1_000 {
            return String(format: "%.0f kbps", Double(bitsPerSecond) / 1_000)
        }
        return "\(bitsPerSecond) bps"
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            content()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }
}

private struct ResolutionRow: View {
    let resolution: CGSize
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolutionName(resolution))
                        .font(.body)
                    Text("\(Int(resolution.width))×\(Int(resolution.height))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func resolutionName(_ size: CGSize) -> String {
        switch Int(size.height) {
        case 2160: return "4K Ultra HD"
        case 1080: return "Full HD"
        case 720:  return "HD"
        case 540:  return "qHD"
        default:   return "\(Int(size.height))p"
        }
    }
}

private struct FrameRateRow: View {
    let fps: Double
    let originalFPS: Double
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                if abs(fps - originalFPS) < 0.5 {
                    Text("\(Int(fps)) fps (Original)")
                } else {
                    Text("\(Int(fps)) fps")
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct BitrateSlider: View {
    @Binding var bitratePercent: Double
    let targetBitrate: Int
    let inputBitrate: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(Int(bitratePercent))%")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Spacer()
                Text(formatBitrate(targetBitrate))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: $bitratePercent,
                in: 10...100,
                step: 5
            )
            .labelsHidden()

            HStack {
                Text("10%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formatBitrate(inputBitrate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatBitrate(_ bitsPerSecond: Int) -> String {
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitsPerSecond) / 1_000_000)
        } else if bitsPerSecond >= 1_000 {
            return String(format: "%.0f kbps", Double(bitsPerSecond) / 1_000)
        }
        return "\(bitsPerSecond) bps"
    }
}

private struct BitrateFooter: View {
    let keepOriginalBitrate: Bool
    let recommendedBitrateText: String
    let selectedFPS: Double
    let selectedResolution: CGSize

    var body: some View {
        Group {
            if keepOriginalBitrate {
                Text("Preserves the original bitrate. Only codec changes.")
            } else {
                let fpsLabel = "\(Int(selectedFPS))fps"
                let resLabel = selectedResolution.height >= 2160 ? "4K" : "\(Int(selectedResolution.height))p"
                Text("\(recommendedBitrateText) recommended for \(resLabel) @ \(fpsLabel). Too low decreases quality.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
