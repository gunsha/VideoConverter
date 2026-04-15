// VideoCache.swift
// VideoConverter

import Foundation
import Photos
import CoreLocation

struct CachedVideoAsset: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let filename: String
    let fileSize: Int64
    let duration: TimeInterval
    let creationDate: Date?
    let modificationDate: Date?
    let resolutionWidth: Double
    let resolutionHeight: Double
    let frameRate: Double
    let codec: String
    let latitude: Double?
    let longitude: Double?
    let isFavorite: Bool

    var resolution: CGSize {
        CGSize(width: resolutionWidth, height: resolutionHeight)
    }

    var locationCoordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    init(from asset: VideoAsset) {
        self.id = asset.id
        self.filename = asset.filename
        self.fileSize = asset.fileSize
        self.duration = asset.duration
        self.creationDate = asset.creationDate
        self.modificationDate = asset.modificationDate
        self.resolutionWidth = asset.resolution.width
        self.resolutionHeight = asset.resolution.height
        self.frameRate = asset.frameRate
        self.codec = asset.codec
        self.latitude = asset.locationCoordinate?.latitude
        self.longitude = asset.locationCoordinate?.longitude
        self.isFavorite = asset.isFavorite
    }

    func toVideoAsset(photoLibraryService: PhotoLibraryService) async -> VideoAsset? {
        await photoLibraryService.fetchVideoAsset(by: id)
    }
}

struct VideoCache: Codable, @unchecked Sendable {
    let assets: [CachedVideoAsset]
    let cachedAt: Date
    let photoLibraryVersion: String

    var isStale: Bool {
        Date().timeIntervalSince(cachedAt) > 86400
    }
}

final class VideoCacheService: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let cacheFileName = "video_cache.json"

    private var cacheURL: URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(cacheFileName)
    }

    func load() async -> VideoCache? {
        guard let url = cacheURL else { return nil }
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(VideoCache.self, from: data)
        } catch {
            return nil
        }
    }

    func save(_ cache: VideoCache) async {
        guard let url = cacheURL else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: url, options: .atomic)
        } catch {
            // Silently fail - cache is non-critical
        }
    }

    func clear() async {
        guard let url = cacheURL else { return }
        try? fileManager.removeItem(at: url)
    }
}
