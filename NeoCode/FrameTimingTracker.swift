import Foundation
import QuartzCore
import os

/// Lightweight frame timing tracker that logs frame drops and slow frames.
/// Activated by setting `NEOCODE_TRACK_FRAMES=1` in the environment.
final class FrameTimingTracker {
    static let shared = FrameTimingTracker()

    private var displayLink: CVDisplayLink?
    private var lastTimestamp: Double = 0
    private var frameCount: Int = 0
    private var dropCount: Int = 0
    private var totalFrames: Int = 0
    private var maxFrameDuration: Double = 0
    private let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "FrameTiming")

    private let frameBudget: Double = 1.0 / 60.0  // 16.67ms
    private let dropThreshold: Double = 1.0 / 60.0 + 0.001  // 17.67ms

    private init() {
        guard ProcessInfo.processInfo.environment["NEOCODE_TRACK_FRAMES"] == "1" else { return }
        start()
    }

    private func start() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink else { return }

        let opaque = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputHandler(displayLink) { [self] _, inNow, _, _, _ -> CVReturn in
            let now = Double(inNow.pointee.videoTime) / Double(inNow.pointee.videoTimeScale)
            if lastTimestamp > 0 {
                let delta = now - lastTimestamp
                totalFrames += 1
                maxFrameDuration = max(maxFrameDuration, delta)
                if delta > dropThreshold {
                    dropCount += 1
                    if delta > 0.02, dropCount % 10 == 1 {
                        logger.warning("Frame drop #\(dropCount): \(String(format: "%.1f", delta * 1000))ms")
                    }
                }
                frameCount += 1
                if frameCount >= 600 {
                    let pct = Double(dropCount) / Double(max(totalFrames, 1)) * 100
                    logger.notice("Frames: \(totalFrames) Drops: \(dropCount) (\(String(format: "%.1f", pct))%) Max: \(String(format: "%.1f", maxFrameDuration * 1000))ms")
                    frameCount = 0
                }
            }
            lastTimestamp = now
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(displayLink)
    }

    deinit {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
}
