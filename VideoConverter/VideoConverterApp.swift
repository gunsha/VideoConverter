// VideoConverterApp.swift
// VideoConverter

import SwiftUI

@main
struct VideoConverterApp: App {

    @State private var photoLibraryService = PhotoLibraryService()
    @State private var listViewModel: VideoListViewModel
    @State private var conversionViewModel = ConversionViewModel()
    @State private var storageAnalysisViewModel = StorageAnalysisViewModel()

    init() {
        let service = PhotoLibraryService()
        _photoLibraryService = State(initialValue: service)
        _listViewModel = State(initialValue: VideoListViewModel(photoLibraryService: service))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(listViewModel)
                .environment(conversionViewModel)
                .environment(storageAnalysisViewModel)
        }
    }
}

