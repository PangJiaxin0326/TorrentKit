# TorrentKit External Dependencies

TorrentKit currently uses the original system-level native dependency model. It does not vendor libtorrent, OpenSSL, Boost, or any XCFramework artifacts.

## System Dependencies

The default paths assume Homebrew on Apple Silicon:

```text
/opt/homebrew/opt/libtorrent-rasterbar
/opt/homebrew/include
/opt/homebrew/lib
```

`Package.swift` links `QBTLibtorrentCBridge` against:

- `libtorrent-rasterbar`
- `ssl`
- `crypto`

It also mirrors the compile definitions exported by the installed `libtorrent-rasterbar.pc`, including OpenSSL support.

## Overrides

Set these environment variables before resolving/building the package when using a different system install:

```sh
export HOMEBREW_PREFIX=/opt/homebrew
export LIBTORRENT_ROOT=/opt/homebrew/opt/libtorrent-rasterbar
```

`HOMEBREW_PREFIX` supplies the shared system include and library roots. `LIBTORRENT_ROOT` supplies libtorrent's own include and library roots.
