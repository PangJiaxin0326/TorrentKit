# TorrentKit

TorrentKit is QBTSwift's standalone torrent-engine package. It owns the Swift-native torrent models, engine protocols, fake engine, and libtorrent-backed implementation.

The package is split into two modules:

- `TorrentKit`: Swift-native models, service protocols, session settings, and fake/unimplemented engines.
- `TorrentKitLibtorrent`: the libtorrent-backed actor and C bridge.

The native bridge links against a system-level libtorrent install, defaulting to Homebrew's `/opt/homebrew/opt/libtorrent-rasterbar`. See `Docs/ExternalDependencies.md` for the dependency contract and override variables.
