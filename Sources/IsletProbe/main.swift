import AppKit
import IsletCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let synthetic = CommandLine.arguments.contains("--synthetic")
let visualizer = CommandLine.arguments.contains("--visualizer")

MainActor.assumeIsolated {
    if visualizer {
        runAudioVisualizerProbe(seconds: 10) { sawSignal in
            print(sawSignal ? "\nRESULT: real audio detected ✅" : "\nRESULT: no audio signal seen ❌")
            exit(sawSignal ? 0 : 1)
        }
    } else {
        runNowPlayingProbe(seconds: 8, injectSynthetic: synthetic) { resolved in
            print(resolved ? "\nRESULT: Now Playing resolved ✅" : "\nRESULT: never resolved ❌")
            exit(resolved ? 0 : 1)
        }
    }
}

app.run()
