// StorageAnalysis.swift
// VideoConverter

import Foundation

struct StorageAnalysis: Codable, Sendable {
    let photoBytes: Int64
    let livePhotoBytes: Int64
    let hevcVideoBytes: Int64
    let nonHevcVideoBytes: Int64
    let scannedAt: Date

    var totalBytes: Int64 {
        photoBytes + livePhotoBytes + hevcVideoBytes + nonHevcVideoBytes
    }
}
