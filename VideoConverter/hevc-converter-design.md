# HEVC Video Converter — Design Document

## Overview

A SwiftUI iOS app that scans the user's photo library for non-HEVC videos, presents them with relevant metadata, and converts them to HEVC (H.265) while preserving the originals and as much metadata as possible.

---

## App Architecture

The app follows **MVVM** (Model-View-ViewModel) with a service layer. This maps cleanly onto SwiftUI's reactive data flow and keeps conversion logic decoupled from the UI.

```
App
├── Models
│   ├── VideoAsset
│   └── ConversionJob
├── ViewModels
│   ├── VideoListViewModel
│   └── ConversionViewModel
├── Views
│   ├── VideoListView
│   ├── VideoRowView
│   ├── ConversionSettingsView
│   ├── ConversionProgressView
│   └── ConversionResultView
└── Services
    ├── PhotoLibraryService
    ├── VideoConversionService
    └── MetadataService
```

---

## Data Models

### `VideoAsset`
Represents a non-HEVC video found in the library.

| Property | Type | Source |
|---|---|---|
| `id` | `String` | PHAsset localIdentifier |
| `phAsset` | `PHAsset` | PhotoKit |
| `filename` | `String` | PHAsset resource |
| `fileSize` | `Int64` | PHAssetResource |
| `duration` | `TimeInterval` | PHAsset |
| `creationDate` | `Date?` | PHAsset |
| `modificationDate` | `Date?` | PHAsset |
| `resolution` | `CGSize` | PHAsset pixelWidth/Height |
| `frameRate` | `Double` | AVAsset tracks |
| `codec` | `String` | AVAssetTrack formatDescriptions |
| `locationCoordinate` | `CLLocationCoordinate2D?` | PHAsset location |
| `isFavorite` | `Bool` | PHAsset |

### `ConversionJob`
Represents a single in-progress or completed conversion.

| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `sourceAsset` | `VideoAsset` | Original |
| `targetResolution` | `CGSize` | User-selected or original |
| `targetFrameRate` | `Double` | User-selected or original |
| `targetBitrate` | `Int?` | Optional override |
| `status` | `ConversionStatus` | `.pending`, `.converting`, `.done`, `.failed` |
| `progress` | `Double` | 0.0 – 1.0 |
| `outputURL` | `URL?` | Temporary file before saving |
| `outputAssetIdentifier` | `String?` | PHAsset ID after saving |
| `error` | `Error?` | If failed |

---

## Services

### `PhotoLibraryService`
Responsible for scanning the photo library.

- Requests `PHAuthorizationStatus` for `.readWrite`
- Fetches all `PHAsset` with `mediaType == .video`
- Filters out assets already in HEVC by loading the `AVURLAsset` and inspecting the video track's `formatDescriptions` for `kCMVideoCodecType_HEVC`
- Returns an array of `VideoAsset` models
- Listens to `PHPhotoLibraryChangeObserver` to refresh if the library changes

### `MetadataService`
Responsible for reading and writing metadata.

**Reading (before conversion):**
- `PHAsset`: creation date, modification date, location, favorite status, burst info, hidden status
- `AVAsset.commonMetadata`: title, description, any embedded tags
- `AVAssetTrack`: codec, resolution, frame rate, bit rate

**Writing (after conversion):**
- Use `AVMutableMetadataItem` to embed metadata into the output file during export
- Save to photo library using `PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:)` and then set:
  - `creationDate` (preserves original timestamp)
  - `location` via `PHAssetChangeRequest.location`
  - `isFavorite` via `PHAssetChangeRequest.isFavorite`
- Album membership can be replicated by fetching the source asset's `PHAssetCollection`s and adding the new asset to the same collections

### `VideoConversionService`
Handles the actual transcoding using `AVAssetExportSession` or `AVAssetWriter`.

**Strategy — two tiers:**

| Scenario | API |
|---|---|
| Resolution/FPS match original | `AVAssetExportSession` with preset or custom `AVOutputSettingsAssistant` |
| Resolution/FPS downscaled | `AVAssetWriter` + `AVAssetReader` with custom `AVVideoComposition` |

`AVAssetExportSession` is simpler and preferred when no transforms are needed. `AVAssetWriter`/`AVAssetReader` gives full control for downscaling, custom FPS, and manual metadata injection.

**Codec settings:**
```
AVVideoCodecKey: AVVideoCodecType.hevc
AVVideoWidthKey / AVVideoHeightKey: target resolution
AVVideoCompressionPropertiesKey:
  AVVideoAverageBitRateKey: computed from resolution (or user override)
  AVVideoProfileLevelKey: HEVC Main or Main10
```

**Audio:** passed through as-is using `AVAssetWriterInput` passthrough, preserving original AAC/AC3.

**Output location:** a temporary file in `FileManager.default.temporaryDirectory` while conversion runs. Saved to the photo library only on completion. Temp file is deleted after successful library import or on cancellation.

---

## ViewModels

### `VideoListViewModel`
- `@Published var videos: [VideoAsset]` — filtered, non-HEVC list
- `@Published var isLoading: Bool`
- `@Published var authorizationStatus: PHAuthorizationStatus`
- `@Published var sortOrder: SortOrder` — by date, size, duration, name
- `@Published var selectedVideos: Set<String>` — for batch operations
- Functions: `load()`, `refresh()`, `selectAll()`, `clearSelection()`

### `ConversionViewModel`
- `@Published var jobs: [ConversionJob]`
- `@Published var activeJobCount: Int`
- Functions: `enqueue(asset:settings:)`, `cancel(job:)`, `cancelAll()`
- Manages a queue with a configurable concurrency limit (default: 1, to avoid thermal pressure)
- Posts `NotificationCenter` updates for background progress

---

## Views

### `VideoListView`
The main screen.

- `NavigationStack` with title "Videos to Convert"
- Toolbar: sort picker, select-all toggle, batch-convert button
- `List` of `VideoRowView` items
- Empty state: shown when all videos are already HEVC or library is empty
- Permission prompt: shown if access is not granted
- Floating "Convert Selected (N)" button when items are selected

### `VideoRowView`
One row per video.

- Thumbnail (async, from `PHImageManager`)
- Filename
- Resolution + FPS badge (e.g., "1920×1080 · 30fps")
- Codec badge (e.g., "H.264", "MPEG-4")
- File size (human-readable: "248 MB")
- Creation date + time
- Duration
- Checkmark for selection mode
- Tap → opens `ConversionSettingsView`

### `ConversionSettingsView`
Sheet presented before starting a conversion.

**Resolution picker:**
- Default: original resolution (e.g., 3840×2160)
- Options: only resolutions ≤ original (e.g., 1920×1080, 1280×720, 960×540)
- Shown as a segmented control or menu

**Frame rate picker:**
- Default: original FPS (e.g., 60fps)
- Options: only FPS values ≤ original (e.g., 30fps, 24fps)
- Common values: 60, 30, 25, 24

**Estimated output size:** live estimate based on resolution, FPS, and a target bitrate heuristic (e.g., ~40% of original H.264 size at same resolution — HEVC's typical efficiency gain)

**Start Conversion** button

### `ConversionProgressView`
Shown in a sheet or as an overlay when conversion is running.

- Per-job progress bars with filename and percentage
- Cancel button per job
- Cancel All button
- Shows completed jobs inline with a checkmark and "Saved to Library" confirmation

### `ConversionResultView`
Post-conversion summary (can be a simple alert or a small card).

- "Conversion complete"
- Original size vs. new size + savings percentage
- "Review & Delete Original" shortcut that opens the Photos app deeplink to the original asset

---

## Metadata Preservation Strategy

| Metadata | Preserved How |
|---|---|
| Creation date | `PHAssetChangeRequest.creationDate` |
| Location (GPS) | `PHAssetChangeRequest.location` |
| Favorite | `PHAssetChangeRequest.isFavorite` |
| Album membership | Re-add new asset to same `PHAssetCollection`s |
| Embedded title/description | `AVMutableMetadataItem` written into output via `AVAssetWriter.metadata` |
| Original filename (stem) | Append `_HEVC` suffix to original stem when saving |
| Hidden status | `PHAssetChangeRequest` (if API permits at time of implementation) |

**What cannot be fully preserved:**
- Burst photo associations (video bursts are rare but worth noting)
- Live Photo pairing (Live Photos with video components should be excluded from the conversion list or handled specially)
- "Memories" curation — these are regenerated automatically by Photos

---

## Edge Cases & Considerations

**Live Photos:** PHAssets that are paired with a still (`.mediaSubtype.contains(.photoLive)`) should be flagged or excluded, as converting their video component separately would break the pairing.

**HDR / Dolby Vision:** Some source videos may be HDR. The export should detect `AVVideoColorPropertiesKey` and pass through HDR metadata where `AVAssetExportSession` / `AVAssetWriter` supports it. Dolby Vision may require special handling or a warning that it will be downgraded to HDR10/SDR.

**Thermal throttling:** On-device encoding is CPU/GPU intensive. The service should observe `ProcessInfo.thermalState` and pause the queue if it reaches `.serious` or `.critical`.

**Background execution:** `AVAssetExportSession` supports background operation via `beginBackgroundTask`. Long conversions should use this to avoid being killed when the app backgrounds.

**Storage check:** Before starting, compare estimated output size against `FileManager` available space in the temporary and photo library volumes and warn the user if space is tight.

**Duplicate guard:** Before saving, check if an asset with the same name + `_HEVC` already exists to prevent double-converting.

---

## Permissions Required (Info.plist)

- `NSPhotoLibraryUsageDescription` — reading videos
- `NSPhotoLibraryAddUsageDescription` — saving converted output
- `NSLocationWhenInUseUsageDescription` — not needed (location is read from asset metadata, not from the device GPS at runtime)

---

## Possible Future Extensions

- iCloud-aware indicator (warn if source is not downloaded locally before converting)
- Watch folder / automatic conversion of newly imported non-HEVC videos
- Share extension to convert a single video from other apps
- Configurable quality preset (file size vs. quality slider mapped to bitrate)
- Batch delete originals after review (multi-select in a "Completed" tab)
