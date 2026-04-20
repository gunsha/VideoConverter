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
