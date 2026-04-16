// StorageAnalysisView.swift
// VideoConverter

import SwiftUI
import Photos
import UIKit

struct StorageAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StorageAnalysisViewModel.self) private var vm

    var body: some View {
        NavigationStack {
            Group {
                if vm.isScanning {
                    scanningView
                } else if vm.authorizationStatus == .denied || vm.authorizationStatus == .restricted {
                    permissionDeniedView
                } else if let analysis = vm.analysis {
                    analysisView(analysis)
                } else {
                    emptyView
                }
            }
            .navigationTitle("Storage Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                if !vm.isScanning {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await vm.scan() }
                        } label: {
                            Label("Scan", systemImage: "arrow.clockwise")
                        }
                        .disabled(vm.authorizationStatus != .authorized && vm.authorizationStatus != .limited)
                    }
                }
            }
        }
        .task { await vm.onAppear() }
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.accentColor)

            if vm.discoveredCount > 0 {
                Text("Found \(vm.discoveredCount) items…")
                    .foregroundStyle(.secondary)
            } else {
                Text("Scanning library…")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Data", systemImage: "chart.pie")
        } description: {
            Text("Tap Scan to analyze your photo library storage.")
        } actions: {
            Button("Scan Library") {
                Task { await vm.scan() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.authorizationStatus == .denied || vm.authorizationStatus == .restricted)
        }
    }

    private var permissionDeniedView: some View {
        ContentUnavailableView {
            Label("Access Denied", systemImage: "lock.fill")
        } description: {
            Text("Please allow photo library access in Settings → Privacy → Photos.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func analysisView(_ analysis: StorageAnalysis) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                totalCard(analysis)

                VStack(spacing: 0) {
                    categoryRow(
                        icon: "video.fill",
                        iconColor: .orange,
                        title: "Videos (HEVC)",
                        subtitle: "Already optimized",
                        count: analysis.hevcVideoCount,
                        bytes: analysis.hevcVideoBytes
                    )
                    Divider().padding(.leading, 52)

                    categoryRow(
                        icon: "video.fill",
                        iconColor: .blue,
                        title: "Videos (Other)",
                        subtitle: "Can be converted",
                        count: analysis.nonHevcVideoCount,
                        bytes: analysis.nonHevcVideoBytes
                    )
                    Divider().padding(.leading, 52)

                    categoryRow(
                        icon: "livephoto",
                        iconColor: .purple,
                        title: "Live Photos",
                        subtitle: "Photos with motion",
                        count: analysis.livePhotoCount,
                        bytes: analysis.livePhotoBytes
                    )
                    Divider().padding(.leading, 52)

                    categoryRow(
                        icon: "photo.fill",
                        iconColor: .green,
                        title: "Photos",
                        subtitle: "Static images",
                        count: analysis.photoCount,
                        bytes: analysis.photoBytes
                    )
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("Last scanned: \(analysis.scannedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private func totalCard(_ analysis: StorageAnalysis) -> some View {
        VStack(spacing: 4) {
            Text("Total")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(ByteCountFormatter.string(fromByteCount: analysis.totalBytes, countStyle: .file))
                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
            Text("\(analysis.totalCount) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func categoryRow(icon: String, iconColor: Color, title: String, subtitle: String, count: Int, bytes: Int64) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body)
                    Text("(\(count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    StorageAnalysisView()
        .environment(StorageAnalysisViewModel())
}
