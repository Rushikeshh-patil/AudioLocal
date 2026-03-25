// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioLocal",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AudioLocal",
            targets: ["AudioLocal"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AudioLocal",
            path: "Sources/AudioLocal",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        )
    ]
)
