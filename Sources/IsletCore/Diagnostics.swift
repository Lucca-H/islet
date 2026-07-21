import AppKit

/// Live diagnostic for the Now Playing pipeline.
///
/// Drives the real `NowPlayingManager` for `seconds` and prints what it resolves,
/// so the shipping code path can be verified end to end from the terminal. Used by
/// the `IsletProbe` target; not part of the app itself.
/// Live diagnostic for the audio visualizer.
///
/// Starts the real `AudioVisualizerEngine` and prints the frequency-band levels it
/// resolves once a second, so it can be confirmed against actually-playing audio
/// (including browser audio, which `NowPlayingManager` structurally can't see).
@MainActor
public func runAudioVisualizerProbe(seconds: Int = 10, onFinish: @escaping (Bool) -> Void) {
    let engine = AudioVisualizerEngine.shared
    print("authorized: \(engine.isAuthorized)")
    guard engine.isAuthorized else {
        print("NOT AUTHORIZED — grant Screen & System Audio Recording first.")
        onFinish(false)
        return
    }
    engine.start()

    var ticks = 0
    var everSawSignal = false

    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
        MainActor.assumeIsolated {
            ticks += 1
            let levels = engine.bars.map { String(format: "%.2f", $0) }.joined(separator: " ")
            if engine.hasSignal { everSawSignal = true }
            print("[\(ticks)s] capturing=\(engine.isCapturing) signal=\(engine.hasSignal) bands=[\(levels)]")
            if ticks >= seconds {
                timer.invalidate()
                engine.stop()
                onFinish(everSawSignal)
            }
        }
    }
}

@MainActor
public func runNowPlayingProbe(seconds: Int = 8,
                               injectSynthetic: Bool = false,
                               onFinish: @escaping (Bool) -> Void) {
    let manager = NowPlayingManager()
    manager.start()

    var ticks = 0
    var everResolved = false

    // Post a notification in exactly the shape Music broadcasts, to verify the
    // notification-handling path without depending on the user's library.
    if injectSynthetic {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("   …injecting synthetic com.apple.iTunes.playerInfo notification")
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.apple.iTunes.playerInfo"),
                object: nil,
                userInfo: [
                    "Name": "Synthetic Test Track",
                    "Artist": "Islet Diagnostics",
                    "Album": "Probe",
                    "Player State": "Playing"
                ],
                deliverImmediately: true
            )
        }
    }

    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
        MainActor.assumeIsolated {
            ticks += 1
            if let info = manager.info {
                everResolved = true
                let symbol = info.isPlaying ? "▶︎" : "❚❚"
                let art = manager.artwork != nil ? "YES" : "no"
                print("[\(ticks)s] \(symbol) \(info.title) — \(info.artist)  [\(info.sourceName)]  artwork=\(art)")
            } else {
                print("[\(ticks)s] (nothing playing)")
            }
            if ticks >= seconds {
                timer.invalidate()
                manager.stop()
                onFinish(everResolved)
            }
        }
    }
}
