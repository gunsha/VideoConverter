// ConversionSettingsView.swift
// VideoConverter

import SwiftUI

struct ConversionSettingsView: View {
    let asset: VideoAsset

    @Environment(\.dismiss) private var dismiss
    @Bindable var conversionVM: ConversionViewModel

    @State private var selectedResolution: CGSize
    @State private var selectedFPS: Double
    @State private var bitratePercent: Double
    @State private var removeHDR: Bool = false
    @State private var keepOriginalBitrate: Bool = false

    private var inputBitrate: Int {
        guard asset.duration > 0 else { return 2_000_000 }
        return max(Int(Double(asset.fileSize * 8) / asset.duration), 500_000)
    }

    private var defaultTargetBitrate: Int {
        let height = asset.resolution.height
        if height >= 1080 {
            return 4_096_000
        } else if height >= 720 {
            return 2_048_000
        } else {
            return Int(Double(inputBitrate) * 0.65)
        }
    }

    private var defaultBitratePercent: Double {
        guard inputBitrate > 0 else { return 65 }
        let height = asset.resolution.height
        if height >= 1080 {
            return min(65, Double(4_096_000) / Double(inputBitrate) * 100)
        } else if height >= 720 {
            return min(65, Double(2_048_000) / Double(inputBitrate) * 100)
        } else {
            return 65
        }
    }

    private var targetBitrate: Int {
        if keepOriginalBitrate {
            return inputBitrate
        }
        return Int(Double(inputBitrate) * (bitratePercent / 100.0))
    }
    
    private var recommendedBitrateText: String {
        if selectedResolution.height >= 2160 {
            return "8 Mbps"
        } else if selectedResolution.height >= 1080 {
            return "4 Mbps"
        } else if selectedResolution.height >= 720 {
            return "2 Mbps"
        } else {
            return "lower"
        }
    }

    private var estimatedBytes: Int64 {
        if keepOriginalBitrate {
            return asset.fileSize
        }
        
        // Calculate estimated size based on actual target bitrate and duration
        let adjustedFPS = min(selectedFPS, asset.frameRate)
        let duration = asset.duration * (adjustedFPS / asset.frameRate)
        
        return MetadataService.estimateSize(bitrate: targetBitrate, durationSeconds: duration)
    }

    private var savings: Int {
        guard asset.fileSize > 0, estimatedBytes > 0 else { return 0 }
        let saved = Double(asset.fileSize - estimatedBytes) / Double(asset.fileSize)
        return max(0, Int((saved * 100).rounded()))
    }

    init(asset: VideoAsset, conversionVM: ConversionViewModel) {
        self.asset = asset
        self.conversionVM = conversionVM
        _selectedResolution = State(initialValue: asset.resolution)
        _selectedFPS        = State(initialValue: asset.frameRate)

        let height = asset.resolution.height
        let sourceBitrate = max(Int(Double(asset.fileSize * 8) / max(asset.duration, 1)), 500_000)
        let targetBitrate: Int
        if height >= 1080 {
            targetBitrate = 4_096_000
        } else if height >= 720 {
            targetBitrate = 2_048_000
        } else {
            targetBitrate = Int(Double(sourceBitrate) * 0.65)
        }
        let calculatedPercent = Double(targetBitrate) / Double(sourceBitrate) * 100
        _bitratePercent = State(initialValue: min(calculatedPercent, 100))
    }

    var body: some View {
        NavigationStack {
            Form {
                // Source info
                Section {
                    LabeledContent("File", value: asset.filename)
                    LabeledContent("Original size", value: asset.formattedFileSize)
                    LabeledContent("Codec",  value: asset.codec)
                    if asset.isHEVC {
                        LabeledContent("Format", value: "HEVC")
                    }
                    if asset.isHDR {
                        LabeledContent("HDR", value: "Yes")
                    } else {
                        LabeledContent("HDR", value: "No")
                    }
                    LabeledContent("Resolution", value: asset.resolutionLabel)
                    LabeledContent("Frame rate", value: asset.frameRateLabel)
                    if let cameraMake = asset.cameraMake {
                        LabeledContent("Camera", value: cameraMake)
                    }
                    if let cameraModel = asset.cameraModel {
                        LabeledContent("Camera model", value: cameraModel)
                    }
                    if let lensMake = asset.lensMake {
                        LabeledContent("Lens make", value: lensMake)
                    }
                    if let lensModel = asset.lensModel {
                        LabeledContent("Lens model", value: lensModel)
                    }
                    if let software = asset.software {
                        LabeledContent("Software", value: software)
                    }
                } header: { Text("Source Video") }

                if asset.isHDR {
                    Section {
                        Toggle("Remove HDR", isOn: $removeHDR)
                    } header: { Text("HDR") } footer: {
                        Text("Removes HDR metadata and tone-maps to SDR Rec.709 for better compatibility.")
                    }
                }

                // Resolution picker
                Section {
                    ForEach(asset.resolutionOptions.indices, id: \.self) { idx in
                        let res = asset.resolutionOptions[idx]
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resolutionName(res))
                                    .font(.body)
                                Text("\(Int(res.width))×\(Int(res.height))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedResolution == res {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation { selectedResolution = res }
                        }
                    }
                } header: { Text("Output Resolution") }

                // Frame rate picker
                Section {
                    ForEach(asset.frameRateOptions.filter { $0 <= asset.frameRate }, id: \.self) { fps in
                        HStack {
                            if abs(fps - asset.frameRate) < 0.5 {
                                Text("Original (\(Int(fps)) fps)")
                            } else {
                                Text("\(Int(fps)) fps")
                            }
                            Spacer()
                            if abs(selectedFPS - fps) < 0.5 {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation { selectedFPS = fps }
                        }
                    }
                } header: { Text("Frame Rate") }

                // Bitrate picker
                Section {
                    Toggle("Keep original bitrate", isOn: $keepOriginalBitrate)

                    if !keepOriginalBitrate {
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
                } header: { Text("Target Bitrate") } footer: {
                    if keepOriginalBitrate {
                        Text("Preserves the original bitrate. Only codec changes.")
                    } else {
                        let fpsLabel = "\(Int(selectedFPS))fps"
                        let resLabel = selectedResolution.height >= 2160 ? "4K" : "\(Int(selectedResolution.height))p"
                        Text("\(recommendedBitrateText) recommended for \(resLabel) @ \(fpsLabel). Too low decreases quality.")
                    }
                }

                // Estimate
                Section {
                    LabeledContent("Estimated HEVC size") {
                        Text(MetadataService.format(bytes: estimatedBytes))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    LabeledContent("Estimated savings") {
                        Text("~\(savings)%")
                            .foregroundStyle(savings >= 30 ? .green : .secondary)
                            .contentTransition(.numericText())
                    }
                } header: { Text("Estimate") }
                .animation(.easeInOut, value: selectedResolution.width)
                .animation(.easeInOut, value: selectedFPS)
            }
            .navigationTitle("Conversion Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Convert") {
                        conversionVM.enqueue(
                            asset: asset,
                            targetResolution: selectedResolution,
                            targetFrameRate: selectedFPS,
                            targetBitrate: targetBitrate,
                            removeHDR: removeHDR,
                            keepOriginalBitrate: keepOriginalBitrate
                        )
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
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

    private func formatBitrate(_ bitsPerSecond: Int) -> String {
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitsPerSecond) / 1_000_000)
        } else if bitsPerSecond >= 1_000 {
            return String(format: "%.0f kbps", Double(bitsPerSecond) / 1_000)
        }
        return "\(bitsPerSecond) bps"
    }
}
