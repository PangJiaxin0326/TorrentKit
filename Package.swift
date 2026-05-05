// swift-tools-version: 6.0

import PackageDescription

let packageRoot = #filePath
    .split(separator: "/")
    .dropLast()
    .joined(separator: "/")

let libtorrentXCFrameworkHeaders = "/" + packageRoot + "/Vendor/libtorrent.xcframework/macos-arm64_x86_64/Headers"
let openSSLXCFrameworkHeaders = "/" + packageRoot + "/Vendor/OpenSSL.xcframework/macos-arm64_x86_64/Headers"

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
                "OpenSSL",
                "QBTLibtorrentCBridge"
            ],
            path: "Sources/TorrentKitLibtorrent"
        ),
        .binaryTarget(
            name: "libtorrent",
            path: "Vendor/libtorrent.xcframework"
        ),
        .binaryTarget(
            name: "OpenSSL",
            path: "Vendor/OpenSSL.xcframework"
        ),
        .target(
            name: "QBTLibtorrentCBridge",
            dependencies: [
                "libtorrent",
                "OpenSSL"
            ],
            path: "Sources/QBTLibtorrentCBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-I", libtorrentXCFrameworkHeaders,
                    "-I", openSSLXCFrameworkHeaders,
                    "-DBOOST_ASIO_ENABLE_CANCELIO",
                    "-DBOOST_ASIO_NO_DEPRECATED",
                    "-DBOOST_SYSTEM_NO_DEPRECATED",
                    "-DBOOST_ASIO_HAS_STD_CHRONO",
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
