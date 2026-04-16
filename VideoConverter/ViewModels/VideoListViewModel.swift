// VideoListViewModel.swift
// VideoConverter

import Foundation
import Photos

@Observable
final class VideoListViewModel {

    // MARK: - Sort order
    enum SortOrder: String, CaseIterable, Identifiable {
        case date     = "Date"
        case size     = "Size"
        case duration = "Duration"
        case name     = "Name"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .date:     return "calendar"
            case .size:     return "externaldrive"
            case .duration: return "timer"
            case .name:     return "textformat"
            }
        }
    }

    // MARK: - Filters
    enum SizeRange: String, CaseIterable, Identifiable {
        case all = "All Sizes"
        case sd = "SD (<720p)"
        case hd = "HD (720p-1080p)"
        case fhd = "Full HD (1080p)"
        case uhd = "4K (2160p)"
        
        var id: String { rawValue }
        
        var range: ClosedRange<Int>? {
            switch self {
            case .all: return nil
            case .sd: return 0...719
            case .hd: return 720...1079
            case .fhd: return 1080...1080
            case .uhd: return 2160...4320
            }
        }
    }
    
    struct FPSFilterOption: Hashable, Identifiable {
        let fps: Double
        var id: Double { fps }
        
        var label: String {
            "\(Int(fps)) FPS"
        }
        
        static let standardValues: [Double] = [24, 25, 30, 60]
        
        static func range(for fps: Double) -> ClosedRange<Double>? {
            switch fps {
            case 24: return 0...24
            case 25: return 24.001...25
            case 30: return 25.001...30
            case 60: return 30.001...60
            default: return nil
            }
        }
    }
    
    static let fpsFilterAll = FPSFilterOption(fps: 0)
    
    // MARK: - State
    private var rawVideos: [VideoAsset] = []
    var videos: [VideoAsset] {
        filtered
    }
    private var filtered: [VideoAsset] = []
    
    var isLoading = false
    var isRefreshing = false
    var discoveredCount: Int = 0
    var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var sortOrder: SortOrder = .date { didSet { applySortOrder() } }
    var sizeFilter: SizeRange = .all { didSet { applyFilters() } }
    var fpsFilter: FPSFilterOption? = nil {
        didSet {
            applyFilters()
            generateFPSOptions()
        }
    }
    var availableFPSOptions: [FPSFilterOption] = []
    var error: String?

    // MARK: - Dependencies
    private let photoLibraryService: PhotoLibraryService
    private let cacheService = VideoCacheService()

    init(photoLibraryService: PhotoLibraryService) {
        self.photoLibraryService = photoLibraryService
    }

    // MARK: - Public API

    func load() async {
        isLoading = true
        error = nil
        discoveredCount = 0

        if authorizationStatus == .notDetermined {
            authorizationStatus = await photoLibraryService.requestAuthorization()
        }

        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            isLoading = false
            return
        }

        if let cached = await loadFromCache() {
            rawVideos = cached
            applyFilters()
            generateFPSOptions()
            isLoading = false
            Task {
                await refreshInBackground()
            }
            return
        }

        await fetchAndCache()
    }

    func refresh() async {
        isLoading = true
        await fetchAndCache()
    }

    // MARK: - Private

    private func loadFromCache() async -> [VideoAsset]? {
        guard let cache = await cacheService.load() else { return nil }

        let identifiers = cache.assets.map { $0.id }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)

        var phAssetMap: [String: PHAsset] = [:]
        assets.enumerateObjects { asset, _, _ in
            phAssetMap[asset.localIdentifier] = asset
        }

        let cachedVideos = cache.assets.map { cached in
            VideoAsset(from: cached, phAsset: phAssetMap[cached.id])
        }
        if cachedVideos.isEmpty { return nil }
        return sorted(cachedVideos, by: sortOrder)
    }

    private func fetchAndCache() async {
        isRefreshing = true
        discoveredCount = 0

        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            isLoading = false
            isRefreshing = false
            return
        }

        let fetched = await photoLibraryService.fetchNonHEVCVideos { [weak self] count in
            Task { @MainActor [weak self] in
                self?.discoveredCount = count
            }
        }

        rawVideos = fetched
        applyFilters()
        generateFPSOptions()
        isLoading = false
        isRefreshing = false

        let cache = VideoCache(
            assets: fetched.map { CachedVideoAsset(from: $0) },
            cachedAt: Date(),
            photoLibraryVersion: ""
        )
        await cacheService.save(cache)
    }

    private func refreshInBackground() async {
        await fetchAndCache()
    }

    func clearCache() async {
        await cacheService.clear()
    }

    private func applyFilters() {
        var result = rawVideos
        
        if let sizeRange = sizeFilter.range {
            result = result.filter { sizeRange.contains(Int($0.resolution.height)) }
        }
        
        if let fps = fpsFilter?.fps, fps > 0, let range = FPSFilterOption.range(for: fps) {
            result = result.filter { range.contains($0.frameRate) }
        }
        
        filtered = sorted(result, by: sortOrder)
    }

    private func generateFPSOptions() {
        let rawFrameRates = Set(rawVideos.map { $0.frameRate })
        let availableStandard = FPSFilterOption.standardValues.filter { standard in
            rawFrameRates.contains { $0 <= standard || (standard == 24 && $0 <= 24) }
        }
        availableFPSOptions = [Self.fpsFilterAll] + availableStandard.map { FPSFilterOption(fps: $0) }
    }

    private func applySortOrder() {
        applyFilters()
    }

    private func sorted(_ assets: [VideoAsset], by order: SortOrder) -> [VideoAsset] {
        switch order {
        case .date:
            return assets.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        case .size:
            return assets.sorted { $0.fileSize > $1.fileSize }
        case .duration:
            return assets.sorted { $0.duration > $1.duration }
        case .name:
            return assets.sorted { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
        }
    }
}
