# VideoConverter - Agent Documentation

## Project Overview

**VideoConverter** is an iOS 26 mobile app for converting videos to HEVC (High-Efficiency Video Coding) format to save storage space. The app allows users to select videos from their photo library, convert them to HEVC, and manage storage analysis.

## Build Configuration

- **Target Device**: iPhone 17 (always use this when building with Xcode)
- **Minimum iOS Version**: iOS 26
- **Architecture**: SwiftUI with MVVM pattern

## Project Structure

```
VideoConverter/
├── VideoConverterApp.swift          # App entry point
├── ContentView.swift                 # Root view container
├── Models/
│   ├── VideoAsset.swift             # Video asset model
│   ├── StorageAnalysis.swift       # Storage analysis model
│   └── ConversionJob.swift        # Conversion job model
├── Views/
│   ├── VideoListView.swift        # Main video list view
│   ├── VideoRowView.swift        # Individual video row
│   ├── VideoPreviewView.swift     # Video preview player
│   ├── ThumbnailView.swift        # Video thumbnail
│   ├── ConversionSettings/ConversionSettingsView.swift  # HEVC conversion settings
│   ├── ConversionSettings/Components/
│   │   ├── ConversionSettingsForm.swift
│   │   ├── EstimatedSizeFooter.swift
│   │   ├── VideoRowHeader.swift
│   │   └── VideoDetailsList.swift
│   ├── ConversionProgress/ConversionProgressView.swift # Conversion progress display
│   ├── ConversionProgress/Components/JobRowView.swift
│   ├── ConversionResultView.swift # Conversion result/savings display
│   └── StorageAnalysisView.swift # Storage analysis dashboard
├── ViewModels/
│   ├── VideoListViewModel.swift  # Video list logic
│   ├── ConversionViewModel.swift # Conversion process logic
│   └── StorageAnalysisViewModel.swift # Storage analysis logic
├── Services/
│   ├── VideoConversionService.swift  # Core HEVC conversion
│   ├── PhotoLibraryService.swift     # Photo library access
│   ├── StorageAnalysisService.swift  # Storage estimation
│   ├── VideoConversionUtils.swift      # Conversion utilities
│   ├── VideoCache.swift               # Video caching
│   └── MetadataService.swift          # Video metadata
└── ShareExtension/
    └── ShareViewController.swift   # Share extension for converting from other apps
```

## Views

| View | Purpose |
|------|---------|
| **VideoListView** | Main screen showing all videos from photo library with selection for conversion |
| **VideoRowView** | Displays video thumbnail, duration, size, and selection checkbox |
| **VideoPreviewView** | AVPlayer-based video preview with playback controls |
| **ThumbnailView** | Async-loaded video thumbnail with loading state |
| **ConversionSettingsView** | Settings panel for HEVC quality (efficiency/quality) |
| **ConversionSettingsForm** | Form for configuring conversion settings |
| **EstimatedSizeFooter** | Estimated output file size display |
| **VideoRowHeader** | Header showing video info in settings |
| **VideoDetailsList** | Detailed video metadata list |
| **ConversionProgressView** | Progress indicator during conversion |
| **JobRowView** | Job progress row display |
| **ConversionResultView** | Shows space savings and conversion status |
| **StorageAnalysisView** | Dashboard showing potential storage savings |

## Services

| Service | Responsibility |
|--------|----------------|
| **PhotoLibraryService** | Access to PhotoKit for video library |
| **VideoConversionService** | Core AVAssetExportSession HEVC conversion |
| **StorageAnalysisService** | Calculate potential space savings |
| **MetadataService** | Extract video metadata (duration, codec, size) |
| **VideoConversionUtils** | Helper functions for conversion |
| **VideoCache** | In-memory cache for video data |

## Maintenance

When code changes affect this documentation, update accordingly.