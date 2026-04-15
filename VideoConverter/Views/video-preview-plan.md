# Video Preview Implementation Plan

This document outlines the implementation strategy for adding a video preview feature to the Video Converter app.

## 1. New Component: `VideoPreviewView`
- **Technology**: Use `AVKit`'s `VideoPlayer`.
- **Purpose**: Provides native playback controls (play/pause, scrubbing, volume) and handles aspect ratios.
- **Presentation**: Use `.fullScreenCover` for an immersive, focus-driven preview experience.

## 2. State Management in `VideoListView`
Add a state variable to track the active preview:
```swift
@State private var previewingAsset: VideoAsset?
```
The presence of a non-nil value will trigger the presentation of the Video​Preview​View.

3. Refined Interaction Logic
To prevent the preview from interfering with the "Convert" settings (the current primary action), we will differentiate between the thumbnail and the info area.

Video​Row​View Changes
• Add an on​Thumbnail​Tap: () -> ​Void closure to the Video​Row​View initializer.
• Wrap the Thumbnail​View within the Video​Row​View with a tap gesture that calls this closure.

Video​List​View Changes
• Handle Taps: In the For​Each loop, pass a closure to Video​Row​View that sets previewing​Asset = asset.
• Integration: The rest of the row (metadata/text area) will continue to trigger the settings​Target (the conversion settings sheet).
• Dismissal: Add a way to dismiss the preview (e.g., a close button or a swipe-down gesture) to return to the list.

4. Summary of Workflow
1. Create VideoPreviewView.swift: Handles AVPlayer and Video​Asset logic.
2. Modify VideoRowView.swift􀰓: Implement the on​Thumbnail​Tap closure.
3. Update VideoListView.swift􀰓:
   • Add previewing​Asset state.
   • Pass the tap closure in the list loop.
   • Add the .full​Screen​Cover modifier.
