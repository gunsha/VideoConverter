// StorageAnalysis.swift
// VideoConverter

import Foundation

struct StorageAnalysis: Codable, Sendable {
    let photoCount: Int
    let livePhotoCount: Int
    let hevcVideoCount: Int
    let nonHevcVideoCount: Int
    let photoBytes: Int64
    let livePhotoBytes: Int64
    let hevcVideoBytes: Int64
    let nonHevcVideoBytes: Int64
    let scannedAt: Date

    var totalBytes: Int64 {
        photoBytes + livePhotoBytes + hevcVideoBytes + nonHevcVideoBytes
    }

    var totalCount: Int {
        photoCount + livePhotoCount + hevcVideoCount + nonHevcVideoCount
    }

    enum CodingKeys: String, CodingKey {
        case photoCount
        case livePhotoCount
        case hevcVideoCount
        case nonHevcVideoCount
        case photoBytes
        case livePhotoBytes
        case hevcVideoBytes
        case nonHevcVideoBytes
        case scannedAt
    }
}
