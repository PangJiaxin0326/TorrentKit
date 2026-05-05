// swift-tools-version: 6.0

import PackageDescription

let homebrewPrefix = Context.environment["HOMEBREW_PREFIX"] ?? "/opt/homebrew"
let libtorrentSystemRoot = Context.environment["LIBTORRENT_ROOT"] ?? "\(homebrewPrefix)/opt/libtorrent-rasterbar"
let systemIncludeRoot = "\(homebrewPrefix)/include"
let systemLibraryRoot = "\(homebrewPrefix)/lib"

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
                    "-I", "\(libtorrentSystemRoot)/include",
                    "-I", systemIncludeRoot,
                    "-DBOOST_ASIO_ENABLE_CANCELIO",
                    "-DBOOST_ASIO_NO_DEPRECATED",
                    "-DBOOST_SYSTEM_NO_DEPRECATED",
                    "-DBOOST_ASIO_HAS_STD_CHRONO",
                    "-DTORRENT_LINKING_SHARED",
                    "-DTORRENT_USE_OPENSSL",
                    "-DTORRENT_USE_LIBCRYPTO",
                    "-DTORRENT_SSL_PEERS",
                    "-DOPENSSL_NO_SSL2",
                    "-DOPENSSL_NO_SSL3",
                    "-DOPENSSL_NO_TLS1",
                    "-DOPENSSL_NO_TLS1_1",
                    "-DOPENSSL_NO_DTLS1"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(libtorrentSystemRoot)/lib",
                    "-L", systemLibraryRoot,
                    "-ltorrent-rasterbar",
                    "-lssl",
                    "-lcrypto"
                ]),
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
