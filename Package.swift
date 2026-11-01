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
            linkerSettings: [
                // Embeds Info.plist in the executable, so macOS can show why
                // the app asks for calendar access (meeting reminders).
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Support/Info.plist"]),
                // Records which SDK the app was built against. SwiftPM's
                // link step leaves it out, so it fell back to the deployment
                // target (13.0), and macOS then drew every window in its
                // pre-Tahoe compatibility style: small corners, a flat
                // sidebar and a grey title strip instead of Liquid Glass.
                // 26.0 is the first SDK with the current design. The first
                // number must match `platforms` above.
                .unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "13.0", "-Xlinker", "26.0"]),
            ]
        )
    ]
)
