[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Z8Z31Y5S5M)

# HDR content notes:

Re-encoding Dolby Vision video through AVAssetWriter preserves the full 10-bit pixel data, PQ transfer function, and BT.2020 color primaries, so the output looks correct on any HDR display. What is lost is the RPU (Reference Processing Unit) metadata track, which carries per-frame dynamic tone mapping instructions that Dolby Vision-aware displays use for scene-by-scene grading. Without it, the output is treated as HDR10 rather than Dolby Vision. For typical iPhone-shot content the visible difference on most consumer displays is minimal, as the DV enhancement on profile 8 is conservative. The limitation is architectural (AVAssetWriter provides no API to write the RPU track) so preserving the full Dolby Vision signal requires a passthrough export, which prevents any re-encoding (resolution, frame rate, or bitrate changes).

| What | Preserved | Notes |
|------|-----------|-------|
| 10-bit pixel data | Yes | Full luminance and color values intact |
| PQ transfer function | Yes | Tone mapping curve is maintained |
| BT.2020 color primaries | Yes | Wide color gamut is preserved |
| HDR badge in Photos.app | Yes | Asset is correctly identified as HDR |
| Dolby Vision RPU track | No | AVAssetWriter has no API to write the per-frame dynamic metadata track |
| Per-frame dynamic tone mapping | No | Display falls back to a static HDR10/HLG curve instead of DV-specific per-frame grading |
| Dolby Vision profile | No | iPhone captures profile 8 (base HDR10 + DV enhancement layer); output becomes profile-less HDR10 |
| Dolby Vision badge in Photos.app | No | Shown as HDR rather than Dolby Vision |
| Compatibility with DV-filtered queries | No | Apps or libraries filtering specifically for Dolby Vision content will not match the output |