#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    QBTLibtorrentBridgeErrorNone = 0,
    QBTLibtorrentBridgeErrorInvalidMagnet = 1,
    QBTLibtorrentBridgeErrorAddTorrentFailed = 2,
    QBTLibtorrentBridgeErrorTimeout = 3,
    QBTLibtorrentBridgeErrorFileSystem = 4,
    QBTLibtorrentBridgeErrorSelfTestFailed = 5,
    QBTLibtorrentBridgeErrorMissingTorrent = 6,
    QBTLibtorrentBridgeErrorUnexpected = 99
};

typedef struct {
    int32_t code;
    char *message;
    char *payloadJSON;
} QBTLibtorrentBridgeResult;

typedef struct {
    bool allowIncomingConnections;
    int32_t listenPort;
    bool enablePortMapping;
    int32_t maximumConnections;
    int32_t maximumConnectionsPerTorrent;
    int32_t downloadLimitBytesPerSecond;
    int32_t uploadLimitBytesPerSecond;
    bool enableDHT;
    bool enableLocalServiceDiscovery;
    bool enablePeerExchange;
    bool limitUTPRate;
    bool includeProtocolOverhead;
    bool limitLocalPeerRates;
    const char *proxyKind;
    const char *proxyHost;
    int32_t proxyPort;
    bool proxyPeerConnections;
    bool proxyHostnames;
    int32_t connectionSpeed;
    int32_t requestQueueSize;
    const char *dhtBootstrapNodes;
} QBTLibtorrentSessionSettings;

QBTLibtorrentBridgeResult qbt_libtorrent_download_magnet(
    const char *magnet,
    const char *savePath,
    const uint8_t *resumeData,
    size_t resumeDataCount,
    double timeout,
    bool metadataOnly,
    bool startImmediately,
    const char *peer
);

QBTLibtorrentBridgeResult qbt_libtorrent_download_torrent_file(
    const char *torrentFile,
    const char *savePath,
    const uint8_t *resumeData,
    size_t resumeDataCount,
    double timeout,
    bool startImmediately
);

QBTLibtorrentBridgeResult qbt_libtorrent_active_torrent_statuses(void);

QBTLibtorrentBridgeResult qbt_libtorrent_start_torrent(const char *infoHash);

QBTLibtorrentBridgeResult qbt_libtorrent_pause_torrent(const char *infoHash);

QBTLibtorrentBridgeResult qbt_libtorrent_remove_torrent(
    const char *infoHash,
    bool deletingFiles
);

QBTLibtorrentBridgeResult qbt_libtorrent_force_start_torrent(const char *infoHash);

QBTLibtorrentBridgeResult qbt_libtorrent_move_torrent(
    const char *infoHash,
    const char *queueMove
);

QBTLibtorrentBridgeResult qbt_libtorrent_set_torrent_limits(
    const char *infoHash,
    int32_t downloadLimitBytesPerSecond,
    int32_t uploadLimitBytesPerSecond
);

QBTLibtorrentBridgeResult qbt_libtorrent_apply_session_settings(
    QBTLibtorrentSessionSettings settings
);

QBTLibtorrentBridgeResult qbt_libtorrent_run_self_test(
    const char *root,
    double timeout
);

void qbt_libtorrent_bridge_result_destroy(QBTLibtorrentBridgeResult result);

#ifdef __cplusplus
}
#endif
