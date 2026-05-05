import Darwin
import Foundation
import QBTLibtorrentCBridge

struct LibtorrentBridgeError: Error, Equatable, LocalizedError, Sendable {
    enum Code: Int32, Sendable {
        case invalidMagnet = 1
        case addTorrentFailed = 2
        case timeout = 3
        case fileSystem = 4
        case selfTestFailed = 5
        case missingTorrent = 6
        case unexpected = 99
    }

    var code: Code
    var message: String

    var errorDescription: String? {
        message
    }
}

struct LibtorrentNativeBridge: Sendable {
    func downloadMagnet(
        _ magnet: String,
        savePath: URL,
        resumeData: Data?,
        timeout: TimeInterval,
        metadataOnly: Bool,
        startImmediately: Bool,
        peer: String?
    ) throws -> [[String: Any]] {
        try magnet.withCString { magnetPointer in
            try Self.fileSystemPath(savePath).withCString { savePathPointer in
                try Self.withResumeData(resumeData) { resumeDataPointer, resumeDataCount in
                    try Self.withOptionalCString(peer) { peerPointer in
                        let result = qbt_libtorrent_download_magnet(
                            magnetPointer,
                            savePathPointer,
                            resumeDataPointer,
                            resumeDataCount,
                            timeout,
                            metadataOnly,
                            startImmediately,
                            peerPointer
                        )
                        return try Self.payloads(from: result)
                    }
                }
            }
        }
    }

    func downloadTorrentFile(
        _ torrentFile: URL,
        savePath: URL,
        resumeData: Data?,
        timeout: TimeInterval,
        startImmediately: Bool
    ) throws -> [[String: Any]] {
        try Self.fileSystemPath(torrentFile).withCString { torrentFilePointer in
            try Self.fileSystemPath(savePath).withCString { savePathPointer in
                try Self.withResumeData(resumeData) { resumeDataPointer, resumeDataCount in
                    let result = qbt_libtorrent_download_torrent_file(
                        torrentFilePointer,
                        savePathPointer,
                        resumeDataPointer,
                        resumeDataCount,
                        timeout,
                        startImmediately
                    )
                    return try Self.payloads(from: result)
                }
            }
        }
    }

    func activeTorrentStatuses() throws -> [[String: Any]] {
        try Self.payloads(from: qbt_libtorrent_active_torrent_statuses())
    }

    func startTorrent(infoHash: String) throws -> [[String: Any]] {
        try infoHash.withCString { infoHashPointer in
            try Self.payloads(from: qbt_libtorrent_start_torrent(infoHashPointer))
        }
    }

    func pauseTorrent(infoHash: String) throws -> [[String: Any]] {
        try infoHash.withCString { infoHashPointer in
            try Self.payloads(from: qbt_libtorrent_pause_torrent(infoHashPointer))
        }
    }

    func removeTorrent(infoHash: String, deletingFiles: Bool) throws -> [[String: Any]] {
        try infoHash.withCString { infoHashPointer in
            try Self.payloads(from: qbt_libtorrent_remove_torrent(infoHashPointer, deletingFiles))
        }
    }

    func forceStartTorrent(infoHash: String) throws -> [[String: Any]] {
        try infoHash.withCString { infoHashPointer in
            try Self.payloads(from: qbt_libtorrent_force_start_torrent(infoHashPointer))
        }
    }

    func moveTorrent(infoHash: String, queueMove: String) throws -> [[String: Any]] {
        try infoHash.withCString { infoHashPointer in
            try queueMove.withCString { queueMovePointer in
                try Self.payloads(from: qbt_libtorrent_move_torrent(infoHashPointer, queueMovePointer))
            }
        }
    }

    func setTorrentLimits(
        infoHash: String,
        downloadLimitBytesPerSecond: Int,
        uploadLimitBytesPerSecond: Int
    ) throws -> [[String: Any]] {
        try infoHash.withCString { infoHashPointer in
            let result = qbt_libtorrent_set_torrent_limits(
                infoHashPointer,
                Self.int32(downloadLimitBytesPerSecond),
                Self.int32(uploadLimitBytesPerSecond)
            )
            return try Self.payloads(from: result)
        }
    }

    func applySessionSettings(
        allowIncomingConnections: Bool,
        listenPort: Int,
        enablePortMapping: Bool,
        maximumConnections: Int,
        maximumConnectionsPerTorrent: Int,
        downloadLimitBytesPerSecond: Int,
        uploadLimitBytesPerSecond: Int,
        enableDHT: Bool,
        enableLocalServiceDiscovery: Bool,
        enablePeerExchange: Bool,
        limitUTPRate: Bool,
        includeProtocolOverhead: Bool,
        limitLocalPeerRates: Bool,
        proxyKind: String,
        proxyHost: String,
        proxyPort: Int,
        proxyPeerConnections: Bool,
        proxyHostnames: Bool,
        connectionSpeed: Int,
        requestQueueSize: Int,
        dhtBootstrapNodes: String
    ) throws {
        try proxyKind.withCString { proxyKindPointer in
            try proxyHost.withCString { proxyHostPointer in
                try dhtBootstrapNodes.withCString { dhtBootstrapNodesPointer in
                    var settings = QBTLibtorrentSessionSettings()
                    settings.allowIncomingConnections = allowIncomingConnections
                    settings.listenPort = Self.int32(listenPort)
                    settings.enablePortMapping = enablePortMapping
                    settings.maximumConnections = Self.int32(maximumConnections)
                    settings.maximumConnectionsPerTorrent = Self.int32(maximumConnectionsPerTorrent)
                    settings.downloadLimitBytesPerSecond = Self.int32(downloadLimitBytesPerSecond)
                    settings.uploadLimitBytesPerSecond = Self.int32(uploadLimitBytesPerSecond)
                    settings.enableDHT = enableDHT
                    settings.enableLocalServiceDiscovery = enableLocalServiceDiscovery
                    settings.enablePeerExchange = enablePeerExchange
                    settings.limitUTPRate = limitUTPRate
                    settings.includeProtocolOverhead = includeProtocolOverhead
                    settings.limitLocalPeerRates = limitLocalPeerRates
                    settings.proxyKind = proxyKindPointer
                    settings.proxyHost = proxyHostPointer
                    settings.proxyPort = Self.int32(proxyPort)
                    settings.proxyPeerConnections = proxyPeerConnections
                    settings.proxyHostnames = proxyHostnames
                    settings.connectionSpeed = Self.int32(connectionSpeed)
                    settings.requestQueueSize = Self.int32(requestQueueSize)
                    settings.dhtBootstrapNodes = dhtBootstrapNodesPointer

                    try Self.throwIfFailure(qbt_libtorrent_apply_session_settings(settings))
                }
            }
        }
    }

    func runSelfTest(root: URL, timeout: TimeInterval) throws -> [[String: Any]] {
        try Self.fileSystemPath(root).withCString { rootPointer in
            try Self.payloads(from: qbt_libtorrent_run_self_test(rootPointer, timeout))
        }
    }

    private static func payloads(from result: QBTLibtorrentBridgeResult) throws -> [[String: Any]] {
        defer {
            qbt_libtorrent_bridge_result_destroy(result)
        }

        try throwIfFailure(result, shouldDestroy: false)
        guard let payloadPointer = result.payloadJSON else {
            return []
        }

        let payloadData = Data(bytes: payloadPointer, count: strlen(payloadPointer))
        let decoded = try JSONSerialization.jsonObject(with: payloadData)
        guard let payloads = decoded as? [[String: Any]] else {
            throw LibtorrentBridgeError(code: .unexpected, message: "libtorrent returned an invalid event payload.")
        }
        return payloads
    }

    private static func throwIfFailure(
        _ result: QBTLibtorrentBridgeResult,
        shouldDestroy: Bool = true
    ) throws {
        defer {
            if shouldDestroy {
                qbt_libtorrent_bridge_result_destroy(result)
            }
        }

        guard result.code != 0 else {
            return
        }

        let messagePointer: UnsafeMutablePointer<CChar>? = result.message
        let message = messagePointer.map { String(cString: UnsafePointer($0)) } ?? "libtorrent bridge failed."
        let code = LibtorrentBridgeError.Code(rawValue: result.code) ?? .unexpected
        throw LibtorrentBridgeError(code: code, message: message)
    }

    private static func withResumeData<Result>(
        _ resumeData: Data?,
        _ body: (UnsafePointer<UInt8>?, Int) throws -> Result
    ) rethrows -> Result {
        guard let resumeData, resumeData.isEmpty == false else {
            return try body(nil, 0)
        }

        return try resumeData.withUnsafeBytes { rawBuffer in
            try body(rawBuffer.bindMemory(to: UInt8.self).baseAddress, rawBuffer.count)
        }
    }

    private static func withOptionalCString<Result>(
        _ value: String?,
        _ body: (UnsafePointer<CChar>?) throws -> Result
    ) rethrows -> Result {
        guard let value else {
            return try body(nil)
        }

        return try value.withCString(body)
    }

    private static func fileSystemPath(_ url: URL) -> String {
        url.path(percentEncoded: false)
    }

    private static func int32(_ value: Int) -> Int32 {
        Int32(clamping: value)
    }
}
