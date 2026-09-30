// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SleepyNotch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SleepyNotch",
            targets: ["SleepyNotch"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SleepyNotch",
            path: "Sources/SleepyNotch"
        )
    ]
)
