# TorrentKit External Dependencies

TorrentKit owns the native torrent-engine dependency chain. Consumers should not point at `/opt/homebrew`, a developer machine install, or any other preinstalled libtorrent copy.

## Binary Dependency

TorrentKit vendors libtorrent and OpenSSL as:

```text
Vendor/libtorrent.xcframework
Vendor/OpenSSL.xcframework
```

The XCFramework layout is:

```text
libtorrent.xcframework/
  Info.plist
  macos-arm64_x86_64/
    Headers/
      libtorrent/
      boost/
      module.modulemap
    libtorrent-rasterbar.a

OpenSSL.xcframework/
  Info.plist
  macos-arm64_x86_64/
    Headers/
      openssl/
      module.modulemap
    libopenssl.a
```

The package manifest exposes these as SwiftPM binary targets named `libtorrent` and `OpenSSL`, and `QBTLibtorrentCBridge` depends on both. The bridge also links Apple's `SystemConfiguration` framework for libtorrent's macOS network-change notifications; this is an SDK framework, not a vendored C++ library.

## Source Provenance

The checked-in XCFramework is rebuilt from GitHub source archives, not from a system library and not by cloning the full libtorrent repository:

- libtorrent archive: `https://github.com/arvidn/libtorrent/releases/download/v2.0.12/libtorrent-rasterbar-2.0.12.tar.gz`
- Boost archive: `https://github.com/boostorg/boost/releases/download/boost-1.84.0/boost-1.84.0.tar.gz`
- OpenSSL archive: `https://github.com/openssl/openssl/releases/download/openssl-3.6.2/openssl-3.6.2.tar.gz`

## Rebuild

Run this from the package directory:

```sh
Scripts/build-libtorrent-xcframework.sh
```

The script downloads release archives into `.build/libtorrent-xcframework/archives`, builds static macOS slices, copies headers, writes module maps, and creates `Vendor/OpenSSL.xcframework` plus `Vendor/libtorrent.xcframework`.

The current bridge builds OpenSSL from the GitHub release archive and points libtorrent's CMake package discovery at that vendored install. libtorrent protocol encryption is explicitly enabled so the archive is built without `TORRENT_DISABLE_ENCRYPTION`.

GnuTLS and Libgcrypt discovery are no longer force-disabled; they remain fallback discovery paths if the build is explicitly configured away from OpenSSL. If those fallbacks are adopted later, package their dependency chain as vendored binary artifacts sourced from GitHub URLs too.
