// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Islet",
    platforms: [
        .macOS("13.0")
    ],
    products: [
        .executable(name: "Islet", targets: ["Islet"])
    ],
    targets: [
        // All app logic lives here so it can be imported by the app entry point,
        // the self-check runner, and the test target.
        .target(
            name: "IsletCore",
            path: "Sources/IsletCore"
        ),
        // Thin executable: just the NSApplication bootstrap.
        .executableTarget(
            name: "Islet",
            dependencies: ["IsletCore"],
            path: "Sources/Islet"
        ),
        // A dependency-free assertion runner that works without Xcode/XCTest
        // (Command Line Tools ship neither XCTest nor swift-testing).
        .executableTarget(
            name: "IsletChecks",
            dependencies: ["IsletCore"],
            path: "Sources/IsletChecks"
        ),
        // Standard swift-testing suite; runs under `swift test` in CI (Xcode present).
        .executableTarget(
            name: "IsletProbe",
            dependencies: ["IsletCore"],
            path: "Sources/IsletProbe"
        ),
        .testTarget(
            name: "IsletTests",
            dependencies: ["IsletCore"],
            path: "Tests/IsletTests"
        )
    ]
)
