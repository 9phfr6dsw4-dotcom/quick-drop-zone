// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuickDropZone",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "QuickDropZoneCore", targets: ["QuickDropZoneCore"]),
        .executable(name: "QuickDropZone", targets: ["QuickDropZoneApp"])
    ],
    targets: [
        .target(name: "QuickDropZoneCore"),
        .executableTarget(name: "QuickDropZoneApp", dependencies: ["QuickDropZoneCore"], path: "Sources/QuickDropZoneApp"),
        .testTarget(name: "QuickDropZoneCoreTests", dependencies: ["QuickDropZoneCore"])
    ],
    swiftLanguageModes: [.v5]
)
