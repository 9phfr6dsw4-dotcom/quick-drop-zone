// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuickDropZone",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "QuickDropZoneCore", targets: ["QuickDropZoneCore"]),
        .executable(name: "Levant", targets: ["QuickDropZoneApp"])
    ],
    dependencies: [
        // Automatic updates. Pinned exactly; the packaged app embeds this framework.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "QuickDropZoneCore"),
        .executableTarget(
            name: "QuickDropZoneApp",
            dependencies: [
                "QuickDropZoneCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/QuickDropZoneApp",
            linkerSettings: [
                // The packaged app keeps Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(name: "QuickDropZoneCoreTests", dependencies: ["QuickDropZoneCore"])
    ],
    swiftLanguageModes: [.v5]
)
