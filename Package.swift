// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Fader",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Fader",
            path: "Sources/Fader",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FaderTests",
            dependencies: ["Fader"],
            path: "Tests/FaderTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
