// ConversionProgressView.swift
// VideoConverter

import SwiftUI

struct ConversionProgressView: View {
    @Bindable var viewModel: ConversionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.jobs.isEmpty {
                    ContentUnavailableView(
                        "No Conversions",
                        systemImage: "film.stack",
                        description: Text("Queue a video to convert it to HEVC.")
                    )
                } else {
                    jobList
                }
            }
            .navigationTitle("Conversions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if viewModel.hasActiveWork {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Cancel All", role: .destructive) {
                            viewModel.cancelAll()
                        }
                    }
                }
                if viewModel.completedJobs.count > 0 && !viewModel.hasActiveWork {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear Done") {
                            withAnimation { viewModel.clearCompleted() }
                        }
                    }
                }
            }
        }
    }

    private var jobList: some View {
        List {
            ForEach(viewModel.jobs) { job in
                JobRowView(job: job) {
                    viewModel.cancel(job: job)
                }
            }
            .onDelete { indexSet in
                indexSet.forEach { i in
                    let job = viewModel.jobs[i]
                    if job.status.isTerminal { viewModel.removeJob(job) }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Individual job row

private struct JobRowView: View {
    let job: ConversionJob
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
                if job.status == .converting || job.status == .pending {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Progress bar (shown only while converting)
            if job.status == .converting {
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
            HStack(spacing: 12) {
                Text(job.sourceAsset.codec)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("HEVC")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)

                Spacer()

                // Savings badge after done
                if job.status == .done, let pct = job.savingsPercent {
                    Text("Saved \(pct)%")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                }

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
}
