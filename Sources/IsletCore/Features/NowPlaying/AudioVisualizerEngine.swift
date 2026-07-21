import Foundation
import ScreenCaptureKit
import AVFoundation
import Accelerate
import os

/// A real-time frequency-band visualizer driven by actual system audio output.
///
/// Uses `ScreenCaptureKit`'s audio capture (`SCStreamConfiguration.capturesAudio`)
/// rather than tapping Music/Spotify directly, since it works no matter what's
/// actually producing sound. This is the same permission category ("Screen & System
/// Audio Recording") apps like Zoom, OBS, and Loom use — heavier than anything else
/// Islet asks for, since it technically implies broad screen-capture capability even
/// though only the audio channel is ever touched. It's opt-in for exactly that
/// reason: `SettingsStore.audioVisualizerEnabled` defaults to `false`, and capture
/// only starts once the user explicitly turns it on.
///
/// A small (2×2) video capture rides along because `SCStream` has no audio-only
/// mode — the video frames are never read. While active, macOS shows its standard
/// screen-recording indicator; that's disclosed in Settings, not hidden.
@MainActor
final class AudioVisualizerEngine: ObservableObject {
    /// Levels for each frequency band, 0...1, smoothed for a pleasant visual decay.
    @Published private(set) var bars: [CGFloat] = Array(repeating: 0, count: bandCount)
    @Published private(set) var isCapturing = false
    /// Refreshed on every `start()` attempt (not read live), so observers — the
    /// Settings status row, chiefly — actually see it flip once permission is
    /// granted mid-session, instead of a stale value that only a coincidental
    /// re-render would happen to refresh.
    @Published private(set) var isAuthorized: Bool = CGPreflightScreenCaptureAccess()

    /// Whether real audio is currently coming through, with a short hold so brief
    /// gaps between tracks (or quiet passages) don't make the bars flicker away.
    ///
    /// This is the *only* way Islet can tell that browser/web audio is playing —
    /// `NowPlayingManager` structurally can't see browsers, but ScreenCaptureKit
    /// captures whatever is actually making sound.
    @Published private(set) var hasSignal = false

    private static let signalThreshold: CGFloat = 0.02
    private static let signalHold: TimeInterval = 1.5
    private var lastSignalAt: Date?
    private var signalTimer: Timer?

    nonisolated static let bandCount = 4
    /// One instance app-wide: Settings shows live status (authorized? capturing?)
    /// from the exact same engine the notch is actually using, not a lookalike.
    static let shared = AudioVisualizerEngine()

    private let log = Logger(subsystem: "com.dynamicisland.islet", category: "AudioVisualizer")
    private var stream: SCStream?
    private let output = AudioOutput()
    private var isStarting = false

    private init() {}

    /// Triggers the system permission prompt the first time; a no-op (returning the
    /// current status) on every call after. Once denied, only System Settings can
    /// change it — there is no in-app re-prompt.
    @discardableResult
    func requestAccess() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        isAuthorized = granted
        return granted
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func start() {
        // Refreshed on every attempt — this is what lets a retry loop notice
        // permission being granted mid-session without anything else re-rendering.
        isAuthorized = CGPreflightScreenCaptureAccess()
        guard !isCapturing, !isStarting, isAuthorized else { return }
        isStarting = true

        output.onBands = { [weak self] bands in
            Task { @MainActor in self?.applyBands(bands) }
        }

        // Expires `hasSignal` once audio actually stops; the sample callback can
        // only ever tell us sound *is* present, never that it went away.
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.expireSignalIfStale() }
        }
        RunLoop.main.add(timer, forMode: .common)
        signalTimer = timer

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    await MainActor.run { self.isStarting = false }
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = false
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                config.showsCursor = false

                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.dynamicisland.islet.audiotap"))
                try await stream.startCapture()

                await MainActor.run {
                    self.stream = stream
                    self.isCapturing = true
                    self.isStarting = false
                }
            } catch {
                self.log.error("Audio visualizer failed to start: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { self.isStarting = false }
            }
        }
    }

    func stop() {
        guard isCapturing || isStarting else { return }
        let toStop = stream
        stream = nil
        isCapturing = false
        isStarting = false
        bars = Array(repeating: 0, count: Self.bandCount)
        hasSignal = false
        lastSignalAt = nil
        signalTimer?.invalidate()
        signalTimer = nil
        Task { try? await toStop?.stopCapture() }
    }

    private func applyBands(_ bands: [CGFloat]) {
        bars = bands
        if (bands.max() ?? 0) > Self.signalThreshold {
            lastSignalAt = Date()
            if !hasSignal { hasSignal = true }
        }
    }

    private func expireSignalIfStale() {
        guard hasSignal, let last = lastSignalAt else { return }
        if Date().timeIntervalSince(last) > Self.signalHold {
            hasSignal = false
        }
    }
}

/// Receives raw audio sample buffers off the main thread and reduces them to a
/// handful of smoothed frequency-band levels via FFT.
private final class AudioOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    var onBands: (([CGFloat]) -> Void)?

    private let fftSize = 1024
    private let fftSetup: FFTSetup
    private let log2n: vDSP_Length
    private var window: [Float]
    private var sampleBuffer: [Float] = []
    private var smoothedBands: [Float]
    private var lastSampleRate: Double = 44100

    override init() {
        log2n = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        smoothedBands = [Float](repeating: 0, count: AudioVisualizerEngine.bandCount)
        super.init()
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = formatDescription.audioStreamBasicDescription else { return }
        guard let blockBuffer = sampleBuffer.dataBuffer else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length, dataPointerOut: &dataPointer) == noErr,
              let dataPointer else { return }

        lastSampleRate = asbd.mSampleRate
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let floatCount = length / MemoryLayout<Float>.size

        dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
            // Mix down to mono regardless of the channel layout.
            var frameIndex = 0
            var i = 0
            while i + channels <= floatCount {
                var sum: Float = 0
                for c in 0..<channels { sum += floats[i + c] }
                self.sampleBuffer.append(sum / Float(channels))
                i += channels
                frameIndex += 1
            }
        }

        processAvailableWindows()
    }

    private func processAvailableWindows() {
        while sampleBuffer.count >= fftSize {
            let chunk = Array(sampleBuffer.prefix(fftSize))
            sampleBuffer.removeFirst(fftSize / 2) // 50% overlap for smoother motion
            let bands = computeBands(chunk)
            let smoothed = smooth(bands)
            onBands?(smoothed.map { CGFloat($0) })
        }
        // Avoid unbounded growth if consumption ever falls behind production.
        if sampleBuffer.count > fftSize * 8 {
            sampleBuffer.removeFirst(sampleBuffer.count - fftSize)
        }
    }

    private func smooth(_ new: [Float]) -> [Float] {
        for i in 0..<smoothedBands.count {
            let target = new[i]
            // Fast attack, slower decay — reads as lively rather than sluggish.
            let rate: Float = target > smoothedBands[i] ? 0.6 : 0.25
            smoothedBands[i] += (target - smoothedBands[i]) * rate
        }
        return smoothedBands
    }

    /// FFT the chunk and reduce it to `AudioVisualizerEngine.bandCount` log-spaced
    /// frequency bands (bass → treble), each normalized to roughly 0...1.
    private func computeBands(_ samples: [Float]) -> [Float] {
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var realp = [Float](repeating: 0, count: fftSize / 2)
        var imagp = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { srcPtr in
                    srcPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Log-spaced band edges from ~40Hz to ~16kHz.
        let bandCount = AudioVisualizerEngine.bandCount
        let nyquist = lastSampleRate / 2
        let minFreq = 40.0
        let maxFreq = min(16000.0, nyquist)
        var edges: [Double] = []
        for i in 0...bandCount {
            let t = Double(i) / Double(bandCount)
            edges.append(minFreq * pow(maxFreq / minFreq, t))
        }

        var bands = [Float](repeating: 0, count: bandCount)
        let binHz = lastSampleRate / Double(fftSize)
        for b in 0..<bandCount {
            let loBin = max(1, Int(edges[b] / binHz))
            let hiBin = min(fftSize / 2 - 1, Int(edges[b + 1] / binHz))
            guard hiBin > loBin else { continue }
            var sum: Float = 0
            for bin in loBin...hiBin { sum += magnitudes[bin] }
            let average = sum / Float(hiBin - loBin + 1)
            // Rough perceptual scaling: sqrt compresses the dynamic range so quiet
            // passages still show some motion instead of sitting near zero.
            bands[b] = min(1, sqrt(average) / 12.0)
        }
        return bands
    }
}
