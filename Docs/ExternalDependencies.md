# TorrentKit External Dependencies

TorrentKit owns the native torrent-engine dependency chain. The host app should not point at `/opt/homebrew`, a developer machine install, or any other preinstalled libtorrent copy.

## Source Dependencies

- libtorrent: `https://github.com/arvidn/libtorrent.git`
  - Default ref: `RC_2_0`
  - Purpose: native BitTorrent session, torrent handle, metadata, alert, and status implementation.
- Boost: `https://github.com/boostorg/boost.git`
  - Default ref: `boost-1.84.0`
  - Purpose: libtorrent's C++ support library dependency, including Boost.Asio and related headers/libraries.

## Bootstrap

Run this from the `TorrentKit` package directory before building the native product:

```sh
Scripts/bootstrap-libtorrent.sh
```

The script clones the GitHub sources into `.build/torrentkit-libtorrent/src`, builds libtorrent with CMake, and installs headers/libraries into `.build/torrentkit-libtorrent/install`. `Package.swift` points the C bridge target at that package-owned install root.

The initial bridge disables libtorrent encryption during bootstrap so TorrentKit does not introduce an OpenSSL source dependency until TLS torrent behavior is migrated. Re-enable that deliberately when the bridge grows SSL/TLS support, and add the OpenSSL GitHub source URL here at the same time.
