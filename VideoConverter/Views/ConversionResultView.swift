// ConversionResultView.swift
// VideoConverter

import SwiftUI

/// Presented as a card overlay when a job completes.
struct ConversionResultView: View {
    let job: ConversionJob
    let onDismiss: () -> Void

    private var isSizeIncreased: Bool {
        guard let pct = job.savingsPercent else { return false }
        return pct < 0
    }

    private var savingsText: String {
        guard let pct = job.savingsPercent else { return "" }
        let out = job.outputFileSize ?? job.sourceAsset.fileSize
        let diffBytes = abs(job.sourceAsset.fileSize - out)
        let formattedDiff = ByteCountFormatter.string(fromByteCount: diffBytes, countStyle: .file)
        
        if pct > 0 {
            return "You saved \(pct)% (\(formattedDiff))"
        } else if pct < 0 {
            return "Size increased by \(abs(pct))% (\(formattedDiff))"
        } else {
            return "Size remained the same"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(.green.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 6) {
                Text("Conversion Complete")
                    .font(.title3.bold())
                Text(job.sourceAsset.filename)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Size comparison
            if let outSize = job.outputFileSize {
                HStack(spacing: 16) {
                    sizeBox(
                        label: "Original",
                        value: ByteCountFormatter.string(fromByteCount: job.sourceAsset.fileSize, countStyle: .file),
                        color: .secondary
                    )
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    sizeBox(
                        label: "HEVC",
                        value: ByteCountFormatter.string(fromByteCount: outSize, countStyle: .file),
                        color: .green
                    )
                }
                .padding(.horizontal)

                if !savingsText.isEmpty {
                    Text(savingsText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(isSizeIncreased ? .orange : .green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background((isSizeIncreased ? Color.orange : Color.green).opacity(0.1), in: Capsule())
                }
            }

            Divider()

            // Actions
            VStack(spacing: 8) {
                if let identifier = job.outputAssetIdentifier, !identifier.isEmpty {
                    Button {
                        openInPhotos(assetIdentifier: identifier)
                    } label: {
                        Label("Review in Photos", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.accentColor)
                }

                Button("Done", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
    }

    private func sizeBox(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
    }

    private func openInPhotos(assetIdentifier: String) {
        // Deep link into Photos app to the specific asset
        let urlString = "photos-redirect://"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
