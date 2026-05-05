# TorrentKit External Dependencies

TorrentKit owns the native torrent-engine dependency chain. Consumers should not point at `/opt/homebrew`, a developer machine install, or any other preinstalled libtorrent copy.

## Binary Dependency

TorrentKit vendors libtorrent as:

```text
Vendor/libtorrent.xcframework
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
```

The package manifest exposes this as a SwiftPM binary target named `libtorrent`, and `QBTLibtorrentCBridge` depends on that target. The bridge also links Apple's `SystemConfiguration` framework for libtorrent's macOS network-change notifications; this is an SDK framework, not a vendored C++ library.

## Source Provenance

The checked-in XCFramework is rebuilt from GitHub source archives, not from a system library and not by cloning the full libtorrent repository:

- libtorrent archive: `https://github.com/arvidn/libtorrent/releases/download/v2.0.12/libtorrent-rasterbar-2.0.12.tar.gz`
- Boost archive: `https://github.com/boostorg/boost/releases/download/boost-1.84.0/boost-1.84.0.tar.gz`

## Rebuild

Run this from the package directory:

```sh
Scripts/build-libtorrent-xcframework.sh
```

The script downloads release archives into `.build/libtorrent-xcframework/archives`, builds static macOS slices with CMake, copies libtorrent and Boost headers, writes `Headers/module.modulemap`, and creates `Vendor/libtorrent.xcframework`.

The current bridge builds libtorrent with protocol encryption and SSL/TLS dependency discovery disabled so the vendored binary does not introduce OpenSSL, GnuTLS, or Libgcrypt runtime/link dependencies. Re-enable HTTPS trackers, HTTPS web seeds, or SSL torrent behavior deliberately, and package any newly required external library as a vendored binary artifact sourced from its GitHub URL.
