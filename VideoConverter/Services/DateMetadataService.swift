// DateMetadataService.swift
// VideoConverter

import Foundation
import Photos

/// Parses a recording date from a video filename and writes it to the Photo Library.
struct DateMetadataService {

    // MARK: - Date Parsing

    /// Attempts to extract a `Date` from a filename whose stem matches
    /// `[VID_]YYYYMMDD_HHMMSS[_suffix][.ext]`.
    ///
    /// Examples:
    ///   - `VID_20231204_153012.mp4`  → 2023-12-04 15:30:12
    ///   - `20231204_153012.MOV`      → 2023-12-04 15:30:12
    ///   - `VID_20231204_153012_1.mp4`→ 2023-12-04 15:30:12
    static func dateFromFilename(_ filename: String) -> Date? {
        // Strip extension
        let stem = (filename as NSString).deletingPathExtension

        // Strip optional "VID_" prefix (case-insensitive)
        let stripped = stem.uppercased().hasPrefix("VID_")
            ? String(stem.dropFirst(4))
            : stem

        // The date part is always the first 15 characters: YYYYMMDD_HHMMSS
        guard stripped.count >= 15 else { return nil }
        let datePart = String(stripped.prefix(15))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.date(from: datePart)
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
