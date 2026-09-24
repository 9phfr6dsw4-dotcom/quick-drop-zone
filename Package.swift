// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuickDropZone",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "QuickDropZoneCore", targets: ["QuickDropZoneCore"])
    ],
    targets: [
        .target(name: "QuickDropZoneCore"),
        .testTarget(name: "QuickDropZoneCoreTests", dependencies: ["QuickDropZoneCore"])
    ]
)
