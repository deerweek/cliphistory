// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipHistory",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClipHistory", targets: ["ClipHistoryApp"])
    ],
    targets: [
        .target(
            name: "ClipHistory",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "ClipHistoryApp",
            dependencies: ["ClipHistory"]
        ),
        .testTarget(
            name: "ClipHistoryTests",
            dependencies: ["ClipHistory"]
        )
    ]
)
