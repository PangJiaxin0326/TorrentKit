# TorrentKit

TorrentKit is QBTSwift's standalone torrent-engine package. It owns the Swift-native torrent models, engine protocols, fake engine, and libtorrent-backed implementation.

The package is split into two modules:

- `TorrentKit`: Swift-native models, service protocols, session settings, and fake/unimplemented engines.
- `TorrentKitLibtorrent`: the libtorrent-backed actor and C bridge.

The native bridge links a vendored SwiftPM binary target:

```text
Vendor/libtorrent.xcframework
```

That XCFramework contains the compiled libtorrent binary plus `Headers/libtorrent`, `Headers/boost`, and `Headers/module.modulemap`, so consumers do not need a system libtorrent install and do not need to clone the libtorrent repository. See `Docs/ExternalDependencies.md` for the dependency contract and rebuild command.
