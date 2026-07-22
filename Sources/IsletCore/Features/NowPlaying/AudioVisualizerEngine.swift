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
    /// Drives the "Capturing — audio detected" vs "no audio right now" status text.
    @Published private(set) var hasSignal = false

    /// Why the last capture attempt failed, surfaced in Settings. Without this the
    /// only symptom is silent dead bars, which is impossible to diagnose.
    @Published private(set) var lastError: String?

    private static let signalThreshold: CGFloat = 0.02
    private static let signalHold: TimeInterval = 1.5
    private var lastSignalAt: Date?
    private var signalTimer: Timer?
    private var hasRequestedAccess = false
    private var hasReceivedAnyBuffer = false

    /// `SCStream` was created with `delegate: nil` — meaning if the capture session
    /// died internally, Islet had **no way to find out**. It would just silently
    /// stop receiving buffers forever, with `isCapturing` stuck at `true` and nothing
    /// to catch or restart it. Two independent guards against that now: the delegate
    /// actually reports `didStopWithError`, and a watchdog restarts capture if no
    /// buffer has arrived in `staleCaptureTimeout` regardless of whether the delegate
    /// fires at all (some SCStream failure modes are known to go quiet without ever
    /// calling back).
    private static let staleCaptureTimeout: TimeInterval = 4
    private var lastBufferAt: Date?
    private let streamDelegate = StreamDelegate()

    /// Mirrors engine state into `UserDefaults` so it can be inspected from a
    /// terminal (`defaults read com.dynamicisland.islet visualizerDebugStatus`).
    /// `os_log` isn't readable back without extra permissions on this setup, and a
    /// silently-dead visualizer gives no other outward signal to debug from.
    private static let debugLogKey = "visualizerDebugLog"
    private static let debugLogCapacity = 20

    /// Appends rather than overwrites. A single-key "latest status" version of this
    /// briefly existed and was actively misleading: several events can fire within
    /// the same second (raw format, then first processed buffer), each overwriting
    /// the last before `defaults read` between them ever got a chance to see it.
    private func recordDebug(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var entries = UserDefaults.standard.stringArray(forKey: Self.debugLogKey) ?? []
        entries.append("[\(stamp)] \(message)")
        if entries.count > Self.debugLogCapacity {
            entries.removeFirst(entries.count - Self.debugLogCapacity)
        }
        UserDefaults.standard.set(entries, forKey: Self.debugLogKey)
        log.info("\(message, privacy: .public)")
    }

    /// Enough bands for the circular visualizer to read as a detailed spectrum
    /// rather than a few chunky blocks. The compact pill bars downsample this via
    /// `compactBars(count:)`, so one FFT feeds both.
    nonisolated static let bandCount = 32
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

    /// Clear Islet's own Screen Recording grant, then quit so the next launch
    /// re-prompts from scratch.
    ///
    /// Needed because Islet is ad-hoc signed: its code hash changes on every rebuild,
    /// and macOS pins the grant to that hash. The stale row left behind in System
    /// Settings still says "Islet" and still looks enabled, but no longer applies to
    /// the running build — and toggling it there doesn't fix it, because the entry
    /// refers to a binary that no longer exists. Resetting is the only way out short
    /// of a stable Developer ID signature.
    func resetPermissionAndQuit() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", "com.dynamicisland.islet"]
        try? process.run()
        process.waitUntilExit()
        NSApp.terminate(nil)
    }

    func start() {
        // Only *request* (which prompts and registers Islet with TCC) once per run;
        // preflight is enough afterwards. The Settings toggle's onChange also calls
        // requestAccess(), but onChange only fires on a transition — if
        // audioVisualizerEnabled was already true from a previous session, opening
        // Settings and seeing it already on triggers nothing, so that path alone
        // could leave Islet never registered at all. Doing it here on the first
        // attempt closes that gap without re-prompting every retry tick.
        if hasRequestedAccess {
            isAuthorized = CGPreflightScreenCaptureAccess()
        } else {
            hasRequestedAccess = true
            isAuthorized = requestAccess()
        }
        guard !isCapturing, !isStarting, isAuthorized else {
            recordDebug("start() skipped — capturing=\(isCapturing) starting=\(isStarting) authorized=\(isAuthorized)")
            return
        }
        isStarting = true
        lastError = nil
        recordDebug("start() proceeding — authorized, opening SCStream")

        output.onBands = { [weak self] bands in
            Task { @MainActor in self?.applyBands(bands) }
        }
        output.onRawFormatLogged = { [weak self] message in
            Task { @MainActor in self?.recordDebug("raw format: \(message)") }
        }
        streamDelegate.onStop = { [weak self] error in
            Task { @MainActor in self?.handleStreamStopped(error) }
        }

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    await MainActor.run {
                        self.isStarting = false
                        self.lastError = "No display available to capture from."
                    }
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

                let stream = SCStream(filter: filter, configuration: config, delegate: streamDelegate)
                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.dynamicisland.islet.audiotap"))
                try await stream.startCapture()

                await MainActor.run {
                    self.stream = stream
                    self.isCapturing = true
                    self.isStarting = false
                    self.lastError = nil
                    self.lastBufferAt = Date() // seeds the watchdog before any real buffer has arrived
                    self.startWatchdogTimer()
                    self.recordDebug("capture STARTED successfully")
                }
            } catch {
                await MainActor.run {
                    self.isStarting = false
                    self.lastError = error.localizedDescription
                    self.recordDebug("capture FAILED: \(error.localizedDescription)")
                }
            }
        }
    }

    /// `SCStreamDelegate` actually reported the session ending. This is the "good"
    /// failure path — the bad one is the watchdog in `checkWatchdog`, for cases that
    /// never call this at all.
    private func handleStreamStopped(_ error: Error?) {
        let message = error?.localizedDescription ?? "(no error — stream ended cleanly)"
        recordDebug("SCStreamDelegate reported stop: \(message)")
        lastError = error?.localizedDescription
        stop()
        // The AppDelegate retry loop only calls start() on state transitions; this
        // stop happened out-of-band, so kick a restart directly rather than waiting
        // for one that may not come.
        start()
    }

    /// One timer covering both failure modes: `hasSignal` expiring after real audio
    /// actually stops, and the stream having gone silent without telling anyone.
    /// Created only once capture genuinely succeeds — an earlier version made the
    /// (then signal-only) timer up-front on every `start()`, so each failed retry
    /// (every 2s) stacked another live timer.
    private func startWatchdogTimer() {
        signalTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.expireSignalIfStale()
                self?.checkWatchdog()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        signalTimer = timer
    }

    private func checkWatchdog() {
        guard isCapturing, let lastBufferAt else { return }
        let silentFor = Date().timeIntervalSince(lastBufferAt)
        guard silentFor > Self.staleCaptureTimeout else { return }
        recordDebug("watchdog: no buffer in \(String(format: "%.1f", silentFor))s while capturing — forcing restart")
        stop()
        start()
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
        lastBufferAt = nil
        signalTimer?.invalidate()
        signalTimer = nil
        Task { try? await toStop?.stopCapture() }
    }

    private func applyBands(_ bands: [CGFloat]) {
        bars = bands
        lastBufferAt = Date()
        let peak = bands.max() ?? 0
        if !hasReceivedAnyBuffer {
            hasReceivedAnyBuffer = true
            recordDebug("first audio buffer received — peak=\(String(format: "%.4f", peak))")
        }
        if peak > Self.signalThreshold {
            lastSignalAt = Date()
            if !hasSignal { hasSignal = true }
        }
    }

    /// Average the full spectrum down to `count` buckets, for the compact collapsed
    /// bars — one FFT drives both the detailed circular view and the mini bars.
    func compactBars(count: Int) -> [CGFloat] {
        guard count > 0, !bars.isEmpty else { return Array(repeating: 0, count: max(0, count)) }
        let bucket = Double(bars.count) / Double(count)
        return (0..<count).map { index in
            let lower = Int(Double(index) * bucket)
            let upper = min(bars.count, max(lower + 1, Int(Double(index + 1) * bucket)))
            let slice = bars[lower..<upper]
            return slice.reduce(0, +) / CGFloat(slice.count)
        }
    }

    private func expireSignalIfStale() {
        guard hasSignal, let last = lastSignalAt else { return }
        if Date().timeIntervalSince(last) > Self.signalHold {
            hasSignal = false
        }
    }
}

/// Reports when `SCStream` ends the capture session on its own.
///
/// Previously `SCStream` was constructed with `delegate: nil`, so a session dying
/// internally (which does happen — SCStream capture is known to be interrupted by a
/// range of system conditions) was completely invisible: no callback, no error, just
/// silence forever. This alone doesn't catch every failure mode — some are known to
/// go quiet without ever calling `didStopWithError` — which is why the engine also
/// runs an independent buffer-arrival watchdog rather than relying on this alone.
private final class StreamDelegate: NSObject, SCStreamDelegate, @unchecked Sendable {
    var onStop: ((Error?) -> Void)?

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error)
    }
}

/// Receives raw audio sample buffers off the main thread and reduces them to a
/// handful of smoothed frequency-band levels via FFT.
private final class AudioOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    var onBands: (([CGFloat]) -> Void)?
    /// Fires once, with a snapshot of the raw format/data before any of this
    /// class's own processing (mixdown, windowing, FFT) touches it — isolates
    /// whether zeroed output originates upstream (silent/garbage capture) or in
    /// this pipeline.
    var onRawFormatLogged: ((String) -> Void)?
    private var hasLoggedRawFormat = false

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
            if !hasLoggedRawFormat {
                hasLoggedRawFormat = true
                let nonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
                let rawPeak = (0..<floatCount).reduce(Float(0)) { max($0, abs(floats[$1])) }
                let sample = (0..<min(8, floatCount)).map { floats[$0] }
                onRawFormatLogged?(
                    "channels=\(channels) rate=\(asbd.mSampleRate) nonInterleaved=\(nonInterleaved) " +
                    "bytesPerFrame=\(asbd.mBytesPerFrame) floatCount=\(floatCount) rawPeak=\(rawPeak) " +
                    "first8=\(sample)"
                )
            }
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
