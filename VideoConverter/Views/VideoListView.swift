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
    @State private var resultJob: ConversionJob?        // completed job overlay
    @State private var isSelectionMode = false

    var body: some View {
        @Bindable var conversionVM = conversionVM
        NavigationStack {
            ZStack(alignment: .bottom) {
                listContent
                    .navigationTitle("Videos to Convert")
                    .toolbar { toolbarItems }

                // Floating action buttons
                floatingButtons
            }
        }
        // Settings sheet (single video)
        .sheet(item: $settingsTarget) { asset in
            ConversionSettingsView(asset: asset, conversionVM: conversionVM)
        }
        // Progress sheet
        .sheet(isPresented: $conversionVM.showingProgress) {
            ConversionProgressView(viewModel: conversionVM)
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
        .onChange(of: conversionVM.completedJobs.count) { _, count in
            if let latest = conversionVM.completedJobs.last, resultJob == nil {
                withAnimation { resultJob = latest }
            }
        }
        .task { await listVM.load() }
        .refreshable { await listVM.refresh() }
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
                    VideoRowView(asset: asset, isSelected: listVM.selectedIDs.contains(asset.id)) {
                        previewingAsset = asset
                    }
                        .onTapGesture {
                            if isSelectionMode {
                                withAnimation(.spring(duration: 0.2)) {
                                    listVM.toggleSelection(asset.id)
                                }
                            } else {
                                settingsTarget = asset
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                settingsTarget = asset
                            } label: {
                                Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .tint(Color.accentColor)
                        }
                }
            }
            .listStyle(.plain)
            .animation(.default, value: listVM.videos.map(\.id))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        @Bindable var listVM = listVM

        // Refresh button
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { await listVM.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(listVM.isLoading || listVM.isRefreshing)
        }

        // Sort menu
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Sort", selection: $listVM.sortOrder) {
                    ForEach(VideoListViewModel.SortOrder.allCases) { order in
                        Label(order.rawValue, systemImage: order.systemImage).tag(order)
                    }
                }
            } label: {
                Label("Sort", systemImage: "line.3.horizontal.decrease.circle")
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

        // Select / Done toggle
        ToolbarItem(placement: .topBarTrailing) {
            Button(isSelectionMode ? "Done" : "Select") {
                withAnimation {
                    isSelectionMode.toggle()
                    if !isSelectionMode { listVM.clearSelection() }
                }
            }
        }
    }

    // MARK: - Floating buttons

    @ViewBuilder
    private var floatingButtons: some View {
        @Bindable var listVM = listVM
        let count = listVM.selectedIDs.count
        if isSelectionMode && count > 0 {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button {
                        listVM.selectAll()
                    } label: {
                        Label("All", systemImage: "checkmark.circle")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)

                    Button {
                        conversionVM.enqueueBatch(assets: listVM.selectedVideos)
                        withAnimation {
                            isSelectionMode = false
                            listVM.clearSelection()
                        }
                    } label: {
                        Label("Convert \(count) Video\(count == 1 ? "" : "s")",
                              systemImage: "film.stack")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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

    private var emptyStateView: some View {
        ContentUnavailableView(
            "All Videos Are HEVC",
            systemImage: "checkmark.seal.fill",
            description: Text("Every video in your library is already in HEVC format. No conversion needed!")
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
