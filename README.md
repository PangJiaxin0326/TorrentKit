# TorrentKit

TorrentKit is QBTSwift's standalone torrent-engine package. It owns the Swift-native torrent models, engine protocols, fake engine, and libtorrent-backed implementation.

The package is split into two modules:

- `TorrentKit`: Swift-native models, service protocols, session settings, and fake/unimplemented engines.
- `TorrentKitLibtorrent`: the libtorrent-backed actor and C bridge.

The native bridge links a vendored SwiftPM binary target:

```text
Vendor/libtorrent.xcframework
Vendor/OpenSSL.xcframework
```

The libtorrent XCFramework contains the compiled libtorrent binary plus `Headers/libtorrent`, `Headers/boost`, and `Headers/module.modulemap`. The OpenSSL XCFramework contains a static `libopenssl.a` built from OpenSSL's GitHub release source. Consumers do not need system libtorrent/OpenSSL installs and do not need to clone the upstream repositories. See `Docs/ExternalDependencies.md` for the dependency contract and rebuild command.
