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

    // MARK: - State
    var videos: [VideoAsset] = []
    var isLoading = false
    var isRefreshing = false
    var discoveredCount: Int = 0
    var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var sortOrder: SortOrder = .date { didSet { applySortOrder() } }
    var selectedIDs: Set<String> = []
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
            videos = cached
            isLoading = false
            Task {
                await refreshInBackground()
            }
            return
        }

        await fetchAndCache()
    }

    func refresh() async {
        await fetchAndCache()
    }

    func selectAll() {
        selectedIDs = Set(videos.map(\.id))
    }

    func clearSelection() {
        selectedIDs = []
    }

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    var selectedVideos: [VideoAsset] {
        videos.filter { selectedIDs.contains($0.id) }
    }

    // MARK: - Private

    private func loadFromCache() async -> [VideoAsset]? {
        guard let cache = await cacheService.load() else { return nil }

        var cachedVideos: [VideoAsset] = []
        for cached in cache.assets {
            if let asset = await photoLibraryService.fetchVideoAsset(by: cached.id) {
                cachedVideos.append(asset)
            }
        }

        if cachedVideos.isEmpty { return nil }
        return sorted(cachedVideos, by: sortOrder)
    }

    private func fetchAndCache() async {
        isRefreshing = true
        discoveredCount = 0

        let fetched = await photoLibraryService.fetchNonHEVCVideos { [weak self] count in
            Task { @MainActor [weak self] in
                self?.discoveredCount = count
            }
        }

        videos = sorted(fetched, by: sortOrder)
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

    private func applySortOrder() {
        videos = sorted(videos, by: sortOrder)
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
