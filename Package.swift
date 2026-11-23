// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ReelsStudio",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ReelsStudio",
            path: "Sources/ReelsStudio",
            linkerSettings: [.linkedFramework("AVKit"), .linkedFramework("AVFoundation")]
        )
    ]
)
