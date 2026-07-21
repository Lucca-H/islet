import AppKit
import IsletCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let synthetic = CommandLine.arguments.contains("--synthetic")

MainActor.assumeIsolated {
    runNowPlayingProbe(seconds: 8, injectSynthetic: synthetic) { resolved in
        print(resolved ? "\nRESULT: Now Playing resolved ✅" : "\nRESULT: never resolved ❌")
        exit(resolved ? 0 : 1)
    }
}

app.run()
