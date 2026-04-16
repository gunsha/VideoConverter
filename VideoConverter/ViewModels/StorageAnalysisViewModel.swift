// StorageAnalysisViewModel.swift
// VideoConverter

import Foundation
import Photos

@Observable
final class StorageAnalysisViewModel {

    private(set) var analysis: StorageAnalysis?
    private(set) var isScanning = false
    private(set) var discoveredCount = 0
    private(set) var authorizationStatus: PHAuthorizationStatus

    private let service = StorageAnalysisService()

    init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func onAppear() async {
        if analysis == nil {
            analysis = await service.loadCached()
        }
    }

    func requestAuthorization() async {
        authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func scan() async {
        guard !isScanning else { return }

        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }

        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return
        }

        isScanning = true
        discoveredCount = 0

        let result = await service.scan(
            authorizationStatus: authorizationStatus
        ) { [weak self] count in
            Task { @MainActor [weak self] in
                self?.discoveredCount = count
            }
        }

        analysis = result
        isScanning = false
        discoveredCount = 0
    }
}
