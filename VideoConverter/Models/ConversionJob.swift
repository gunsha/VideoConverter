// ConversionJob.swift
// VideoConverter

import Foundation

// MARK: - Status enum
enum ConversionStatus: Equatable {
    case pending
    case converting
    case done
    case failed(Error)

    static func == (lhs: ConversionStatus, rhs: ConversionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending), (.converting, .converting), (.done, .done): return true
        case (.failed, .failed): return true
        default: return false
        }
    }

    var isTerminal: Bool { self == .done || isFailed }
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
    var errorMessage: String? {
        if case .failed(let e) = self { return e.localizedDescription }
        return nil
    }
}

// MARK: - ConversionJob
@Observable
final class ConversionJob: Identifiable {
    let id = UUID()
    let sourceAsset: VideoAsset
    let targetResolution: CGSize
    let targetFrameRate: Double
    let targetBitrate: Int?
    let removeHDR: Bool
    let keepOriginalBitrate: Bool
    let outputName: String?
    let outputPrefix: String?
    let outputSuffix: String?

    var status: ConversionStatus = .pending
    var progress: Double = 0.0
    var outputURL: URL?
    var outputAssetIdentifier: String?

    // Saved file size (populated after successful save)
    var outputFileSize: Int64?

    init(
        sourceAsset: VideoAsset,
        targetResolution: CGSize,
        targetFrameRate: Double,
        targetBitrate: Int? = nil,
        removeHDR: Bool = false,
        keepOriginalBitrate: Bool = false,
        outputName: String? = nil,
        outputPrefix: String? = nil,
        outputSuffix: String? = nil
    ) {
        self.sourceAsset = sourceAsset
        self.targetResolution = targetResolution
        self.targetFrameRate = targetFrameRate
        self.targetBitrate = targetBitrate
        self.removeHDR = removeHDR
        self.keepOriginalBitrate = keepOriginalBitrate
        self.outputName = outputName
        self.outputPrefix = outputPrefix
        self.outputSuffix = outputSuffix
    }

    var outputFilename: String {
        let stem = (sourceAsset.filename as NSString).deletingPathExtension
        let ext = (sourceAsset.filename as NSString).pathExtension.isEmpty ? "mov" : (sourceAsset.filename as NSString).pathExtension
        let name = outputName ?? stem
        let prefix = outputPrefix ?? ""
        let suffix = outputSuffix ?? ""
        return "\(prefix)\(name)\(suffix).\(ext)"
    }

    // Estimated savings once done (only valid when outputFileSize is known)
    var savingsPercent: Int? {
        guard let out = outputFileSize, sourceAsset.fileSize > 0 else { return nil }
        let saved = Double(sourceAsset.fileSize - out) / Double(sourceAsset.fileSize)
        return Int((saved * 100).rounded())
    }
}
