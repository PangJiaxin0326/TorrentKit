// swift-tools-version: 6.0

import PackageDescription

let packageRoot = #filePath
    .split(separator: "/")
    .dropLast()
    .joined(separator: "/")

let libtorrentXCFrameworkHeaders = "/" + packageRoot + "/Vendor/libtorrent.xcframework/macos-arm64_x86_64/Headers"

let package = Package(
    name: "TorrentKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TorrentKit",
            targets: ["TorrentKit", "TorrentKitLibtorrent"]
        ),
        .library(
            name: "TorrentKitCore",
            targets: ["TorrentKit"]
        )
    ],
    targets: [
        .target(
            name: "TorrentKit",
            path: "Sources/TorrentKit"
        ),
        .target(
            name: "TorrentKitLibtorrent",
            dependencies: [
                "TorrentKit",
                "libtorrent",
                "QBTLibtorrentCBridge"
            ],
            path: "Sources/TorrentKitLibtorrent"
        ),
        .binaryTarget(
            name: "libtorrent",
            path: "Vendor/libtorrent.xcframework"
        ),
        .target(
            name: "QBTLibtorrentCBridge",
            dependencies: [
                "libtorrent"
            ],
            path: "Sources/QBTLibtorrentCBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-I", libtorrentXCFrameworkHeaders,
                    "-DBOOST_SYSTEM_NO_DEPRECATED",
                    "-DBOOST_ASIO_HAS_STD_CHRONO"
                ])
            ],
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .testTarget(
            name: "TorrentKitTests",
            dependencies: ["TorrentKit"],
            path: "Tests/TorrentKitTests"
        ),
        .testTarget(
            name: "TorrentKitLibtorrentTests",
            dependencies: [
                "TorrentKit",
                "TorrentKitLibtorrent"
            ],
            path: "Tests/TorrentKitLibtorrentTests"
        )
    ],
    cxxLanguageStandard: .cxx20
)
