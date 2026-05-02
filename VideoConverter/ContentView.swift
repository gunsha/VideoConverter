// ContentView.swift
// VideoConverter

import SwiftUI

struct ContentView: View {
    @Environment(ConversionViewModel.self) private var conversionVM
    
    @State private var selectedAsset: VideoAsset?
    @State private var isLoadingAsset = false
    @State private var photoLibraryService = PhotoLibraryService()
    
    var body: some View {
        ZStack {
            VideoListView()
            
            VStack {
                Spacer()
                VideoPickerButton(
                    label: "Convert Video",
                    onError: { error in
                        print("Video picker error: \(error.localizedDescription)")
                    },
                    onPick: { result in
                        loadVideoAsset(identifier: result.localIdentifier)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .sheet(item: $selectedAsset) { asset in
            ConversionSettingsView(asset: asset, conversionVM: conversionVM)
        }
        .overlay {
            if isLoadingAsset {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Loading video...")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
    
    private func loadVideoAsset(identifier: String) {
        isLoadingAsset = true
        Task {
            if let asset = await photoLibraryService.fetchVideoAsset(by: identifier) {
                await MainActor.run {
                    selectedAsset = asset
                    isLoadingAsset = false
                }
            } else {
                print("Failed to load video asset with identifier: \(identifier)")
                await MainActor.run {
                    isLoadingAsset = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(VideoListViewModel(photoLibraryService: PhotoLibraryService()))
        .environment(ConversionViewModel())
        .environment(StorageAnalysisViewModel())
}

