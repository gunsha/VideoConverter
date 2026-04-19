// VideoAsset.swift
// VideoConverter

import Foundation
import Photos
import CoreLocation

struct VideoAsset: Identifiable, Hashable, Sendable {
    let id: String
    let phAsset: PHAsset?
    let filename: String
    let fileSize: Int64
    let duration: TimeInterval
    let creationDate: Date?
    let modificationDate: Date?
    let resolution: CGSize
    let frameRate: Double
    let codec: String
    let isHDR: Bool
    let locationCoordinate: CLLocationCoordinate2D?
    let isFavorite: Bool
    let lensMake: String?
    let lensModel: String?
    let cameraMake: String?
    let cameraModel: String?
    let software: String?

    static func == (lhs: VideoAsset, rhs: VideoAsset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    
    init(from cached: CachedVideoAsset, phAsset: PHAsset? = nil) {
        self.id = cached.id
        self.phAsset = phAsset
        self.filename = cached.filename
        self.fileSize = cached.fileSize
        self.duration = cached.duration
        self.creationDate = cached.creationDate
        self.modificationDate = cached.modificationDate
        self.resolution = cached.resolution
        self.frameRate = cached.frameRate
        self.codec = cached.codec
        self.isHDR = cached.isHDR
        self.locationCoordinate = cached.locationCoordinate
        self.isFavorite = cached.isFavorite
        self.lensMake = cached.lensMake
        self.lensModel = cached.lensModel
        self.cameraMake = cached.cameraMake
        self.cameraModel = cached.cameraModel
        self.software = cached.software
    }

    init(id: String, phAsset: PHAsset?, filename: String, fileSize: Int64, duration: TimeInterval, creationDate: Date?, modificationDate: Date?, resolution: CGSize, frameRate: Double, codec: String, isHDR: Bool, locationCoordinate: CLLocationCoordinate2D?, isFavorite: Bool, lensMake: String? = nil, lensModel: String? = nil, cameraMake: String? = nil, cameraModel: String? = nil, software: String? = nil) {
        self.id = id
        self.phAsset = phAsset
        self.filename = filename
        self.fileSize = fileSize
        self.duration = duration
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.resolution = resolution
        self.frameRate = frameRate
        self.codec = codec
        self.isHDR = isHDR
        self.locationCoordinate = locationCoordinate
        self.isFavorite = isFavorite
        self.lensMake = lensMake
        self.lensModel = lensModel
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.software = software
    }
}

extension VideoAsset {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDuration: String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    var resolutionLabel: String {
        "\(Int(resolution.width))×\(Int(resolution.height))"
    }

    var frameRateLabel: String {
        let fps = frameRate.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(frameRate))fps"
            : String(format: "%.1ffps", frameRate)
        return fps
    }

    var isHEVC: Bool {
        codec.lowercased().contains("hevc") || codec.lowercased().contains("hvc1")
    }

    var resolutionOptions: [CGSize] {
        let standards: [CGSize] = [
            CGSize(width: 3840, height: 2160),
            CGSize(width: 1920, height: 1080),
            CGSize(width: 1280, height: 720),
            CGSize(width: 960,  height: 540),
        ]
        return standards.filter { $0.width <= resolution.width && $0.height <= resolution.height }
    }

    var frameRateOptions: [Double] {
        var options: [Double] = [60, 30, 25, 24]
        if !options.contains(frameRate) {
            options.append(frameRate)
        }
        return options.sorted()
    }
}
