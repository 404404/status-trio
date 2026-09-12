// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusTrio",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "StatusTrioCore",
            path: "Sources/StatusTrioCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Network"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .testTarget(
            name: "StatusTrioCoreTests",
            dependencies: ["StatusTrioCore"],
            path: "Tests/StatusTrioCoreTests"
        )
    ]
)
