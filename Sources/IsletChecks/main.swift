import AppKit
import IsletCore

// Runs the built-in self-checks and exits non-zero on any failure.
let failures = MainActor.assumeIsolated { runIsletSelfChecks() }
exit(failures == 0 ? 0 : 1)
