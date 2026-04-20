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

    private var targetBitrate: Int {
        if keepOriginalBitrate {
            return inputBitrate
        }
        return Int(Double(inputBitrate) * (bitratePercent / 100.0))
    }

    init(asset: VideoAsset, conversionVM: ConversionViewModel) {
        self.asset = asset
        self.conversionVM = conversionVM
        _selectedResolution = State(initialValue: asset.resolution)
        _selectedFPS        = State(initialValue: asset.frameRate)

        let recommendedBitrate = VideoConversionUtils.recommendedHEVCBitrate(
            width: Int(asset.resolution.width),
            height: Int(asset.resolution.height),
            fps: asset.frameRate
        )
        let sourceBitrate = max(Int(Double(asset.fileSize * 8) / max(asset.duration, 1)), 500_000)
        let calculatedPercent = Double(recommendedBitrate) / Double(sourceBitrate) * 100
        _bitratePercent = State(initialValue: min(calculatedPercent, 100))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        VideoRowHeader(asset: asset)

                        VideoDetailsList(asset: asset)

                        ConversionSettingsForm(
                            asset: asset,
                            selectedResolution: $selectedResolution,
                            selectedFPS: $selectedFPS,
                            bitratePercent: $bitratePercent,
                            removeHDR: $removeHDR,
                            keepOriginalBitrate: $keepOriginalBitrate
                        )
                    }
                    .padding(16)
                    .padding(.bottom, 80)
                }

                EstimatedSizeFooter(
                    asset: asset,
                    selectedResolution: selectedResolution,
                    selectedFPS: selectedFPS,
                    bitratePercent: bitratePercent,
                    keepOriginalBitrate: keepOriginalBitrate
                )
                .padding(16)
                .background(.ultraThinMaterial)
            }
            .background(Color(.systemGroupedBackground))
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
}
