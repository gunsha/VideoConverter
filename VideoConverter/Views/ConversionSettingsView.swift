// ConversionSettingsView.swift
// VideoConverter

import SwiftUI

struct ConversionSettingsView: View {
    let asset: VideoAsset

    @Environment(\.dismiss) private var dismiss
    @Bindable var conversionVM: ConversionViewModel

    @State private var selectedResolution: CGSize
    @State private var selectedFPS: Double
    @State private var bitratePercent: Double = 65

    private var inputBitrate: Int {
        guard asset.duration > 0 else { return 2_000_000 }
        return max(Int(Double(asset.fileSize * 8) / asset.duration), 500_000)
    }

    private var targetBitrate: Int {
        Int(Double(inputBitrate) * (bitratePercent / 100.0))
    }

    private var estimatedBytes: Int64 {
        MetadataService.estimatedOutputBytes(
            sourceBytes: asset.fileSize,
            sourceResolution: asset.resolution,
            sourceFPS: asset.frameRate,
            targetResolution: selectedResolution,
            targetFPS: selectedFPS
        )
    }

    private var savings: Int {
        guard asset.fileSize > 0 else { return 0 }
        let saved = Double(asset.fileSize - max(estimatedBytes, 1)) / Double(asset.fileSize)
        return max(0, Int((saved * 100).rounded()))
    }

    init(asset: VideoAsset, conversionVM: ConversionViewModel) {
        self.asset = asset
        self.conversionVM = conversionVM
        _selectedResolution = State(initialValue: asset.resolution)
        _selectedFPS        = State(initialValue: asset.frameRate)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Source info
                Section {
                    LabeledContent("File", value: asset.filename)
                    LabeledContent("Original size", value: asset.formattedFileSize)
                    LabeledContent("Codec",  value: asset.codec)
                    LabeledContent("Resolution", value: asset.resolutionLabel)
                    LabeledContent("Frame rate", value: asset.frameRateLabel)
                } header: { Text("Source Video") }

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
                    ForEach(asset.frameRateOptions, id: \.self) { fps in
                        HStack {
                            Text("\(Int(fps)) fps")
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
                } header: { Text("Target Bitrate") } footer: {
                    Text("Lower values = smaller files. 65% is recommended for good quality.")
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
                            targetBitrate: targetBitrate
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
