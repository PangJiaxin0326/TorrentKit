// swift-tools-version: 6.0

import PackageDescription

let packageRoot = #filePath
    .split(separator: "/")
    .dropLast()
    .joined(separator: "/")

let libtorrentInstallRoot = "/" + packageRoot + "/.build/torrentkit-libtorrent/install"

// Native source dependencies are fetched by Scripts/bootstrap-libtorrent.sh because
// arvidn/libtorrent is not a SwiftPM package and has no Package.swift manifest.
let libtorrentGitURL = "https://github.com/arvidn/libtorrent.git"
let boostGitURL = "https://github.com/boostorg/boost.git"
_ = (libtorrentGitURL, boostGitURL)

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
                "QBTLibtorrentCBridge"
            ],
            path: "Sources/TorrentKitLibtorrent"
        ),
        .target(
            name: "QBTLibtorrentCBridge",
            path: "Sources/QBTLibtorrentCBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-I", "\(libtorrentInstallRoot)/include",
                    "-DBOOST_SYSTEM_NO_DEPRECATED",
                    "-DBOOST_ASIO_HAS_STD_CHRONO",
                    "-DTORRENT_LINKING_SHARED"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(libtorrentInstallRoot)/lib",
                    "-ltorrent-rasterbar"
                ])
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
