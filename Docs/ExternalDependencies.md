# TorrentKit External Dependencies

TorrentKit owns the native torrent-engine dependency boundary. This rollback version intentionally relies on a system libtorrent-rasterbar install instead of vendored XCFrameworks.

## System Dependencies

The pre-XCFramework package links against a system-level libtorrent-rasterbar install.

Default locations:

- libtorrent: `/opt/homebrew/opt/libtorrent-rasterbar`
- headers shared by Homebrew dependencies: `/opt/homebrew/include`
- libraries shared by Homebrew dependencies: `/opt/homebrew/lib`

Override locations with:

```sh
HOMEBREW_PREFIX=/usr/local swift build
LIBTORRENT_ROOT=/path/to/libtorrent-rasterbar swift build
```

The bridge links `torrent-rasterbar`, `ssl`, and `crypto`, plus the macOS `SystemConfiguration` framework used by Homebrew libtorrent builds.
