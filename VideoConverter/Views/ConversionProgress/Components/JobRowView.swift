// JobRowView.swift
// VideoConverter

import SwiftUI

struct JobRowView: View {
    @Bindable var job: ConversionJob
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                statusIcon
                    .font(.title3)
                Text(job.sourceAsset.filename)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                
                if job.status == .done, let pct = job.savingsPercent {
                    Text("Saved \(pct)%")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                }
                
                if job.status == .converting || job.status == .pending {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // iCloud download phase
            if job.status == .converting, let dlProgress = job.downloadProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: dlProgress)
                        .tint(.blue)
                        .animation(.linear(duration: 0.3), value: dlProgress)
                    Label(
                        dlProgress < 0.01
                            ? "Downloading from iCloud…"
                            : "Downloading from iCloud… \(Int(dlProgress * 100))%",
                        systemImage: "icloud.and.arrow.down"
                    )
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .contentTransition(.numericText())
                }
            }

            // Encoding phase
            if job.status == .converting, job.downloadProgress == nil {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: job.progress)
                        .tint(Color.accentColor)
                        .animation(.linear(duration: 0.3), value: job.progress)
                    Text("\(Int(job.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

            // Result info
            HStack(spacing: 6) {
                // Codec
                BadgeLabel("HEVC", color: .green)
                
                // Resolution
                BadgeLabel("\(Int(job.targetResolution.width))×\(Int(job.targetResolution.height))", color: .blue)
                
                // FPS
                BadgeLabel(targetFrameRateLabel, color: .purple)

                // Bitrate
                if let bitrateLabel = targetBitrateLabel {
                    BadgeLabel(bitrateLabel, color: .orange)
                }
                
                // HDR
                if job.removeHDR {
                    BadgeLabel("HDR Off", color: .red)
                }

                Spacer()

                // Error message
                if let msg = job.status.errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .pending:
            Image(systemName: "clock.fill")
                .foregroundStyle(.secondary)
        case .converting:
            ProgressView()
                .tint(Color.accentColor)
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
    
    private var targetFrameRateLabel: String {
        let fps = job.targetFrameRate.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(job.targetFrameRate))fps"
            : String(format: "%.1ffps", job.targetFrameRate)
        return fps
    }
    
    private var targetBitrateLabel: String? {
        if job.keepOriginalBitrate {
            return nil
        }
        guard let bitsPerSecond = job.targetBitrate else { return nil }
        
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitsPerSecond) / 1_000_000)
        } else if bitsPerSecond >= 1_000 {
            return String(format: "%.0f kbps", Double(bitsPerSecond) / 1_000)
        }
        return "\(bitsPerSecond) bps"
    }
}

// MARK: - Badge helper
private struct BadgeLabel: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}
