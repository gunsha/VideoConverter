// ConversionViewModel.swift
// VideoConverter

import Foundation

@Observable
final class ConversionViewModel {

    // MARK: - State
    var jobs: [ConversionJob] = []
    var showingProgress = false

    var activeJobCount: Int { jobs.filter { $0.status == .converting }.count }
    var pendingJobCount: Int { jobs.filter { $0.status == .pending }.count }
    var completedJobs: [ConversionJob] { jobs.filter { $0.status == .done } }
    var hasActiveWork: Bool { activeJobCount > 0 || pendingJobCount > 0 }

    // MARK: - Private
    private let maxConcurrent = 1
    private let service = VideoConversionService.shared
    private var queueTask: Task<Void, Never>?

    // MARK: - Public API

    /// Enqueues a single job from ConversionSettingsView.
    func enqueue(asset: VideoAsset, targetResolution: CGSize, targetFrameRate: Double, targetBitrate: Int? = nil, removeHDR: Bool = false, keepOriginalBitrate: Bool = false) {
        // Duplicate guard: skip if already queued or done
        guard !jobs.contains(where: { $0.sourceAsset.id == asset.id && !$0.status.isTerminal }) else { return }

        let job = ConversionJob(
            sourceAsset: asset,
            targetResolution: targetResolution,
            targetFrameRate: targetFrameRate,
            targetBitrate: targetBitrate,
            removeHDR: removeHDR,
            keepOriginalBitrate: keepOriginalBitrate
        )
        jobs.append(job)
        showingProgress = true
        startQueueIfNeeded()
    }

    /// Enqueues multiple jobs for batch conversion (uses original resolution/fps).
    func enqueueBatch(assets: [VideoAsset], removeHDR: Bool = false, keepOriginalBitrate: Bool = false) {
        let newJobs = assets
            .filter { a in !jobs.contains(where: { $0.sourceAsset.id == a.id && !$0.status.isTerminal }) }
            .map { ConversionJob(sourceAsset: $0, targetResolution: $0.resolution, targetFrameRate: $0.frameRate, removeHDR: removeHDR, keepOriginalBitrate: keepOriginalBitrate) }
        guard !newJobs.isEmpty else { return }
        jobs.append(contentsOf: newJobs)
        showingProgress = true
        startQueueIfNeeded()
    }

    func cancel(job: ConversionJob) {
        // For .pending jobs we can cancel immediately; for .converting we can only mark
        if case .pending = job.status {
            job.status = .failed(CancellationError())
        }
    }

    func cancelAll() {
        queueTask?.cancel()
        queueTask = nil
        for job in jobs where job.status == .pending || job.status == .converting {
            job.status = .failed(CancellationError())
        }
    }

    func clearCompleted() {
        jobs.removeAll { $0.status.isTerminal }
    }

    func removeJob(_ job: ConversionJob) {
        jobs.removeAll { $0.id == job.id }
    }

    // MARK: - Queue management

    private func startQueueIfNeeded() {
        guard queueTask == nil else { return }
        queueTask = Task { [weak self] in
            await self?.processQueue()
        }
    }

    private func processQueue() async {
        defer { queueTask = nil }
        while !Task.isCancelled {
            let pending = jobs.filter { $0.status == .pending }
            guard !pending.isEmpty else { break }

            let running = jobs.filter { $0.status == .converting }.count
            guard running < maxConcurrent else {
                try? await Task.sleep(for: .milliseconds(300))
                continue
            }

            if let next = pending.first {
                // Fire-and-forget for this job; loop continues once it finishes
                await processJob(next)
            }
        }
    }

    private func processJob(_ job: ConversionJob) async {
        guard job.status == .pending else { return }
        job.status = .converting

        do {
            let outputURL = try await service.convert(job: job) { @MainActor progress in
                job.progress = progress
            }
            job.outputURL = outputURL

            // Capture file size before moving to library
            let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
            let outSize = attrs?[.size] as? Int64

            // Save to library
            let identifier = try await service.saveToPhotoLibrary(url: outputURL, originalAsset: job.sourceAsset)
            job.outputAssetIdentifier = identifier
            job.outputFileSize = outSize

            // Clean up temp file
            try? FileManager.default.removeItem(at: outputURL)

            job.status = .done
            job.progress = 1.0

        } catch is CancellationError {
            job.status = .failed(CancellationError())
        } catch {
            job.status = .failed(error)
        }
    }
}
