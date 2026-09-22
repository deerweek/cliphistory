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
        // On Linux there is no SQLite3 system module in the toolchain (macOS
        // ships one in its SDK). Provide one via a module map so the core
        // library builds on both platforms.
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(
            name: "ClipHistory",
            dependencies: [
                .target(name: "CSQLite", condition: .when(platforms: [.linux]))
            ],
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
