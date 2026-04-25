// FixDateConfirmationView.swift
// VideoConverter

import SwiftUI
import Photos

/// Shown when the user swipes left → "Fix Date" on a video whose filename
/// contains a valid date stamp.
struct FixDateConfirmationView: View {
    let asset: VideoAsset
    let proposedDate: Date
    var onConfirm: () async throws -> Void
    var onCancel: () -> Void

    @State private var isSaving = false
    @State private var saveError: String?

    // MARK: - Formatters
    private let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                // Header card
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Date Mismatch Detected", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        Text("The creation date stored in your Photo Library doesn't match the date embedded in the filename. Would you like to update it?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // File info
                Section("File") {
                    LabeledContent("Name", value: asset.filename)
                }

                // Date comparison
                Section("Date Information") {
                    LabeledContent("Current (incorrect)") {
                        if let current = asset.creationDate {
                            Text(fullFormatter.string(from: current))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.trailing)
                        } else {
                            Text("None")
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("From filename") {
                        Text(fullFormatter.string(from: proposedDate))
                            .foregroundStyle(.green)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // Error (if any)
                if let error = saveError {
                    Section {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Fix Creation Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Apply") {
                            Task {
                                isSaving = true
                                saveError = nil
                                do {
                                    try await onConfirm()
                                } catch {
                                    saveError = error.localizedDescription
                                }
                                isSaving = false
                            }
                        }
                        .bold()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
