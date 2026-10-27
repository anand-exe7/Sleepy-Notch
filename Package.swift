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
            path: "Sources/SleepyNotch",
            // Embeds Info.plist in the executable, so macOS can show why the
            // app asks for calendar access (meeting reminders).
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Support/Info.plist"])
            ]
        )
    ]
)
