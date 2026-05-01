// DateMetadataService.swift
// VideoConverter

import Foundation
import Photos

/// Parses a recording date from a video filename and writes it to the Photo Library.
struct DateMetadataService {

    // MARK: - Date Parsing

    /// Attempts to extract a `Date` from a filename whose stem matches
    /// `[PREFIX]YYYYMMDD_HHMMSS[_suffix][.ext]`.
    /// Supported prefixes are `VID_`, `TRIM_`, and `PXL_`.
    ///
    /// Examples:
    ///   - `VID_20231204_153012.mp4`  → 2023-12-04 15:30:12
    ///   - `20231204_153012.MOV`      → 2023-12-04 15:30:12
    ///   - `PXL_20231204_153012_1.mp4`→ 2023-12-04 15:30:12
    static func dateFromFilename(_ filename: String) -> Date? {
        // Strip extension
        let stem = (filename as NSString).deletingPathExtension

        // Strip optional prefixes (case-insensitive)
        let uppercasedStem = stem.uppercased()
        var stripped = stem
        let prefixes = ["VID_", "TRIM_", "PXL_"]
        for prefix in prefixes {
            if uppercasedStem.hasPrefix(prefix) {
                stripped = String(stem.dropFirst(prefix.count))
                break
            }
        }

        // The date part is always the first 15 characters: YYYYMMDD_HHMMSS
        guard stripped.count >= 15 else { return nil }
        let datePart = String(stripped.prefix(15))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        
        guard let parsedDate = formatter.date(from: datePart) else { return nil }
        
        // Don't allow dates in the future
        if parsedDate > Date() {
            return nil
        }
        
        return parsedDate
    }

    // MARK: - Writing to Photo Library

    /// Updates the `creationDate` (and `modificationDate`) of the given `PHAsset`.
    /// Returns `true` on success.
    static func applyDate(_ date: Date, to phAsset: PHAsset) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: phAsset)
            request.creationDate = date
        }
    }
}
