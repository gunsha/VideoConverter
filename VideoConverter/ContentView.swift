// ContentView.swift
// VideoConverter

import SwiftUI

struct ContentView: View {
    @Environment(ConversionViewModel.self) private var conversionVM
    
    var body: some View {
        VideoListView()
    }
}

#Preview {
    ContentView()
        .environment(VideoListViewModel(photoLibraryService: PhotoLibraryService()))
        .environment(ConversionViewModel())
        .environment(StorageAnalysisViewModel())
}

