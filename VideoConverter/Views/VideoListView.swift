// VideoListView.swift
// VideoConverter

import SwiftUI
import Photos

struct VideoListView: View {
    @Environment(VideoListViewModel.self) private var listVM
    @Environment(ConversionViewModel.self) private var conversionVM

    @State private var settingsTarget: VideoAsset?      // tapped single video
    @State private var previewingAsset: VideoAsset?
    @State private var showingProgress = false
    @State private var showingStorageAnalysis = false
    @State private var resultJob: ConversionJob?        // completed job overlay
    @State private var fixDateItem: FixDateItem?        // fix-date swipe action
    @State private var showRefreshConfirmation = false  // refresh toast
    @State private var showRefreshAlert = false          // refresh confirmation dialog
    @State private var dragOffset: CGFloat = 0
    private let refreshThreshold: CGFloat = 80
    
    @State private var isLoadingPickerAsset = false
    @State private var pickerViewModel = VideoPickerViewModel()
    @State private var pickerPhotoLibraryService = PhotoLibraryService()

    var body: some View {
        @Bindable var conversionVM = conversionVM
        NavigationStack {
            listContent
                .navigationTitle("Video Library")
                .toolbar { toolbarItems }
        }
        // Settings sheet (single video)
        .sheet(item: $settingsTarget) { asset in
            ConversionSettingsView(asset: asset, conversionVM: conversionVM)
        }
        // Video picker sheet
        .sheet(isPresented: $pickerViewModel.isPresented) {
            VideoPHPicker(isPresented: $pickerViewModel.isPresented, viewModel: pickerViewModel)
                .ignoresSafeArea()
        }
        // Progress sheet
        .sheet(isPresented: $conversionVM.showingProgress) {
            ConversionProgressView(viewModel: conversionVM)
        }
        // Storage analysis sheet
        .sheet(isPresented: $showingStorageAnalysis) {
            StorageAnalysisView()
        }
        // Fix date confirmation sheet
        .sheet(item: $fixDateItem) { item in
            FixDateConfirmationView(
                asset: item.asset,
                proposedDate: item.date,
                onConfirm: {
                    guard let phAsset = item.asset.phAsset else { return }
                    try await DateMetadataService.applyDate(item.date, to: phAsset)
                    fixDateItem = nil
                    await listVM.updateAssetDate(id: item.asset.id, newDate: item.date)
                },
                onCancel: { fixDateItem = nil }
            )
        }
        // Video preview
        .fullScreenCover(item: $previewingAsset) { asset in
            VideoPreviewView(asset: asset) {
                previewingAsset = nil
            }
        }
        // Result overlay for last completed job
        .overlay {
            if let job = resultJob {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { withAnimation { resultJob = nil } }

                ConversionResultView(job: job) {
                    withAnimation { resultJob = nil }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: resultJob?.id)
        // Watch for newly completed jobs
        .onChange(of: conversionVM.completedJobs.count) { _, _ in
            if let latest = conversionVM.completedJobs.last, resultJob == nil {
                withAnimation { resultJob = latest }
            }
        }
        .onChange(of: conversionVM.hasActiveWork) { _, hasActive in
            if !hasActive && conversionVM.completedJobs.count > 0 {
                conversionVM.showingProgress = false
            }
        }
        .task { await listVM.load() }
        .refreshable {
            showRefreshAlert = true
        }
        .overlay(alignment: .top) {
            if showRefreshConfirmation {
                RefreshConfirmationView()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation { showRefreshConfirmation = false }
                        }
                    }
            }
        }
        .overlay {
            if isLoadingPickerAsset || pickerViewModel.isLoading {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Loading video…")
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: showRefreshConfirmation)
        .animation(.spring(duration: 0.25), value: isLoadingPickerAsset)
        .alert("Refresh Library", isPresented: $showRefreshAlert) {
            Button("Refresh") {
                Task {
                    await listVM.refresh()
                    showRefreshConfirmation = true
                }
            }
            Button("Cancel", role: .cancel) {
                showRefreshAlert = false
            }
        } message: {
            Text("Scan your photo library for new videos?")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var listContent: some View {
        @Bindable var listVM = listVM
        if listVM.isLoading {
            loadingView

        } else if listVM.authorizationStatus == .denied || listVM.authorizationStatus == .restricted {
            permissionDeniedView

        } else if listVM.authorizationStatus == .notDetermined {
            permissionRequestView

        } else if listVM.videos.isEmpty {
            emptyStateView

        } else {
            List {
                ForEach(listVM.videos) { asset in
                    VideoRowView(asset: asset, isSelected: false) {
                        previewingAsset = asset
                    }
                        .onTapGesture {
                            settingsTarget = asset
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                settingsTarget = asset
                            } label: {
                                Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .tint(Color.accentColor)

                            // Fix Date action — only shown when a valid date can be
                            // parsed from the filename.
                            if let proposed = DateMetadataService.dateFromFilename(asset.filename) {
                                Button {
                                    fixDateItem = FixDateItem(asset: asset, date: proposed)
                                } label: {
                                    Label("Fix Date", systemImage: "calendar.badge.exclamationmark")
                                }
                                .tint(.orange)
                            }
                        }
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .animation(.default, value: listVM.videos.map(\.id))
            .safeAreaInset(edge: .bottom) {
                videoStatsFooter(
                    count: listVM.videos.count,
                    totalSize: listVM.videos.reduce(0) { $0 + $1.fileSize }
                )
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        @Bindable var listVM = listVM

        // Add video button
        ToolbarItem(placement: .topBarLeading) {
            Button {
                pickerViewModel.onPick = { result in
                    self.loadVideoFromPicker(identifier: result.localIdentifier)
                }
                pickerViewModel.onError = { error in
                    print("Video picker error: \(error.localizedDescription)")
                }
                pickerViewModel.isPresented = true
            } label: {
                if isLoadingPickerAsset {
                    ProgressView()
                } else {
                    Image(systemName: "plus")
                }
            }
            .disabled(isLoadingPickerAsset)
        }

        // Filter & Sort menu
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Section("Filter") {
                    Picker("Size", selection: $listVM.sizeFilter) {
                        ForEach(VideoListViewModel.SizeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }.pickerStyle(.menu)

                    Picker("Frame Rate", selection: $listVM.fpsFilter) {
                        Text("All").tag(nil as VideoListViewModel.FPSFilterOption?)
                        ForEach(listVM.availableFPSOptions.filter { $0.fps > 0 }) { option in
                            Text(option.label).tag(option as VideoListViewModel.FPSFilterOption?)
                        }
                    }
                    .pickerStyle(.menu)

                    if listVM.sizeFilter != .all || listVM.fpsFilter != nil {
                        Button("Clear Filters") {
                            listVM.sizeFilter = .all
                            listVM.fpsFilter = nil
                        }
                    }
                    Picker("Sort", selection: $listVM.sortOrder) {
                        ForEach(VideoListViewModel.SortOrder.allCases) { order in
                            Label(order.rawValue, systemImage: order.systemImage).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } label: {
                Label(
                    "Filter & Sort",
                    systemImage: listVM.sizeFilter != .all || listVM.fpsFilter != nil
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
        }

        // Progress button (shows badge with active count)
        ToolbarItem(placement: .topBarTrailing) {
            if !conversionVM.jobs.isEmpty {
                Button {
                    conversionVM.showingProgress = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .symbolEffect(.rotate, isActive: conversionVM.hasActiveWork)
                        .foregroundStyle(conversionVM.hasActiveWork ? Color.accentColor : .secondary)
                }
            }
        }

        // Storage analysis button
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingStorageAnalysis = true
            } label: {
                Label("Storage", systemImage: "chart.pie")
            }
        }
    }
    
    private func loadVideoFromPicker(identifier: String) {
        isLoadingPickerAsset = true
        Task {
            if let asset = await pickerPhotoLibraryService.fetchVideoAsset(by: identifier) {
                await MainActor.run {
                    settingsTarget = asset
                    isLoadingPickerAsset = false
                }
            } else {
                print("Failed to load video asset with identifier: \(identifier)")
                await MainActor.run {
                    isLoadingPickerAsset = false
                }
            }
        }
    }

    // MARK: - State views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.accentColor)
            if listVM.discoveredCount > 0 {
                Text("Found \(listVM.discoveredCount) video\(listVM.discoveredCount == 1 ? "" : "s")…")
                    .foregroundStyle(.secondary)
            } else {
                Text("Scanning library…")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func videoStatsFooter(count: Int, totalSize: Int64) -> some View {
        let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)

        HStack {
            Text("\(count) video\(count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(sizeStr)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Videos Found",
            systemImage: "video.slash",
            description: Text("No videos in your photo library.")
        )
    }

    private var permissionRequestView: some View {
        ContentUnavailableView {
            Label("Photo Library Access", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("HEVC Converter needs access to your photos to find and convert videos.")
        } actions: {
            Button("Grant Access") {
                Task { await listVM.load() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var permissionDeniedView: some View {
        ContentUnavailableView {
            Label("Access Denied", systemImage: "lock.fill")
        } description: {
            Text("Please allow photo library access in Settings → Privacy → Photos.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}



// MARK: - Fix Date item (Identifiable wrapper for sheet(item:))
private struct FixDateItem: Identifiable {
    let asset: VideoAsset
    let date: Date
    var id: String { asset.id }
}

// MARK: - Refresh Confirmation Toast

private struct RefreshConfirmationView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Library refreshed")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(radius: 4, y: 2)
        .padding(.top, 8)
    }
}

