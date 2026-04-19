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

    var body: some View {
        @Bindable var conversionVM = conversionVM
        NavigationStack {
            listContent
                .navigationTitle("Videos to Convert")
                .toolbar { toolbarItems }
        }
        // Settings sheet (single video)
        .sheet(item: $settingsTarget) { asset in
            ConversionSettingsView(asset: asset, conversionVM: conversionVM)
        }
        // Progress sheet
        .sheet(isPresented: $conversionVM.showingProgress) {
            ConversionProgressView(viewModel: conversionVM)
        }
        // Storage analysis sheet
        .sheet(isPresented: $showingStorageAnalysis) {
            StorageAnalysisView()
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
        .modifier(RefreshableModifier(
            isEnabled: !listVM.isLoading && !listVM.isRefreshing,
            refreshAction: { await listVM.refresh() }
        ))
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

        // Refresh button
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { await listVM.refresh() }
            } label: {
                if listVM.isLoading || listVM.isRefreshing {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }

        // Filter menu
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Section("Size") {
                    Picker("Size", selection: $listVM.sizeFilter) {
                        ForEach(VideoListViewModel.SizeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Frame Rate") {
                    Picker("FPS", selection: $listVM.fpsFilter) {
                        Text("All").tag(nil as VideoListViewModel.FPSFilterOption?)
                        ForEach(listVM.availableFPSOptions.filter { $0.fps > 0 }) { option in
                            Text(option.label).tag(option as VideoListViewModel.FPSFilterOption?)
                        }
                    }
                }
                if listVM.sizeFilter != .all || listVM.fpsFilter != nil {
                    Divider()
                    Button("Clear Filters") {
                        listVM.sizeFilter = .all
                        listVM.fpsFilter = nil
                    }
                }
            } label: {
                Label("Filter", systemImage: listVM.sizeFilter != .all || listVM.fpsFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
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

        // Storage analysis button
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingStorageAnalysis = true
            } label: {
                Label("Storage", systemImage: "chart.pie")
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

private struct RefreshableModifier: ViewModifier {
    let isEnabled: Bool
    let refreshAction: () async -> Void

    @State private var isRefreshing = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isRefreshing {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: RefreshKey.self,
                            value: [RefreshPreference(reference: geo.frame(in: .global).origin)]
                        )
                    }
                    .frame(height: 0)
                }
            }
            .onPreferenceChange(RefreshKey.self) { preferences in
                guard isEnabled, let pref = preferences.first else { return }
                if -pref.reference.y > 80 {
                    isRefreshing = true
                    Task {
                        await refreshAction()
                        await MainActor.run { isRefreshing = false }
                    }
                }
            }
    }
}

private struct RefreshPreference: Equatable {
    let reference: CGPoint
}

private struct RefreshKey: PreferenceKey {
    static var defaultValue: [RefreshPreference] { [] }

    static func reduce(value: inout [RefreshPreference], nextValue: () -> [RefreshPreference]) {
        value.append(contentsOf: nextValue())
    }
}
