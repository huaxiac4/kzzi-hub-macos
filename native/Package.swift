// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KZZIHub",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "KZZIHub",
            resources: [.copy("Resources")]
        )
    ]
)
