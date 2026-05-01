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
    @Binding var outputName: String
    @Binding var outputPrefix: String
    @Binding var outputSuffix: String

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

            SettingsSection(title: "Output Filename") {
                FilenameFields(
                    name: $outputName,
                    prefix: $outputPrefix,
                    suffix: $outputSuffix,
                    originalFilename: asset.filename
                )
            }

            SettingsSection(title: "Output Resolution") {
                let options: [CGSize] = {
                    var opts = asset.resolutionOptions
                    if !opts.contains(asset.resolution) {
                        opts.append(asset.resolution)
                        opts.sort(by: { $0.height > $1.height })
                    }
                    return opts
                }()
                ForEach(options.indices, id: \.self) { idx in
                    let res = options[idx]
                    ResolutionRow(
                        resolution: res,
                        originalResolution: asset.resolution,
                        isSelected: selectedResolution == res,
                        onTap: { withAnimation { selectedResolution = res } }
                    )
                    if idx < options.count - 1 {
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

                    BitratePresets(
                        bitratePercent: $bitratePercent,
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
    let originalResolution: CGSize
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
        let name: String
        switch Int(size.height) {
        case 2160: name = "4K Ultra HD"
        case 1080: name = "Full HD"
        case 720:  name = "HD"
        case 540:  name = "qHD"
        default:   name = "\(Int(size.height))p"
        }
        
        if size == originalResolution {
            return "\(name) (Original)"
        }
        return name
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

private struct BitratePresets: View {
    @Binding var bitratePercent: Double
    let inputBitrate: Int

    private let presets: [(label: String, bps: Int)] = [
        ("1 Mbps", 1_000_000),
        ("2 Mbps", 2_000_000),
        ("3 Mbps", 3_000_000),
        ("4 Mbps", 4_000_000),
        ("5 Mbps", 5_000_000)
    ]

    private var availablePresets: [(label: String, bps: Int)] {
        presets.filter { Double($0.bps) < Double(inputBitrate) * 0.9 }
    }

    var body: some View {
        if !availablePresets.isEmpty {
            let columns = [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(availablePresets, id: \.bps) { preset in
                    Button {
                        let percent = max(10, min(100, (Double(preset.bps) / Double(inputBitrate)) * 100))
                        withAnimation {
                            bitratePercent = percent
                        }
                    } label: {
                        Text(preset.label)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

private struct FilenameFields: View {
    @Binding var name: String
    @Binding var prefix: String
    @Binding var suffix: String
    let originalFilename: String

    private var previewName: String {
        let stem = (originalFilename as NSString).deletingPathExtension
        let ext = (originalFilename as NSString).pathExtension.isEmpty ? "mov" : (originalFilename as NSString).pathExtension
        let actualName = name.isEmpty ? stem : name
        return "\(prefix)\(actualName)\(suffix).\(ext)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name (leave empty to keep original)", text: $name)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prefix")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. Converted_", text: $prefix)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Suffix")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. _HEVC", text: $suffix)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }

            HStack {
                Text("Preview:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(previewName)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
