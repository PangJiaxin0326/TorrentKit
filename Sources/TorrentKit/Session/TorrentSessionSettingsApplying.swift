import Foundation

public protocol TorrentSessionSettingsApplying: Sendable {
    func apply(_ settings: TorrentSessionSettings) async throws
}

public struct TorrentSessionSettingsChange: Equatable, Sendable {
    public var connectionChanged: Bool
    public var proxyChanged: Bool
    public var speedChanged: Bool
    public var bitTorrentRuntimeChanged: Bool
    public var advancedChanged: Bool
    public var maximumConnectionsChanged: Bool
    public var dhtChanged: Bool
    public var localDiscoveryChanged: Bool

    public var hasRuntimeChanges: Bool {
        connectionChanged || proxyChanged || speedChanged || bitTorrentRuntimeChanged || advancedChanged
    }

    public var peerExchangeChanged: Bool
}

public struct TorrentSessionSettingsDiff {
    public init() {}

    public func changes(from oldValue: TorrentSessionSettings, to newValue: TorrentSessionSettings) -> TorrentSessionSettingsChange {
        TorrentSessionSettingsChange(
            connectionChanged: oldValue.connection != newValue.connection,
            proxyChanged: oldValue.proxy != newValue.proxy,
            speedChanged: oldValue.speed != newValue.speed,
            bitTorrentRuntimeChanged: oldValue.bitTorrent.isDHTEnabled != newValue.bitTorrent.isDHTEnabled
                || oldValue.bitTorrent.isLSDEnabled != newValue.bitTorrent.isLSDEnabled
                || oldValue.bitTorrent.isPeXEnabled != newValue.bitTorrent.isPeXEnabled,
            advancedChanged: oldValue.advanced != newValue.advanced,
            maximumConnectionsChanged: oldValue.connection.maximumConnections != newValue.connection.maximumConnections,
            dhtChanged: oldValue.bitTorrent.isDHTEnabled != newValue.bitTorrent.isDHTEnabled,
            localDiscoveryChanged: oldValue.bitTorrent.isLSDEnabled != newValue.bitTorrent.isLSDEnabled,
            peerExchangeChanged: oldValue.bitTorrent.isPeXEnabled != newValue.bitTorrent.isPeXEnabled
        )
    }
}

public struct NoopTorrentSessionSettingsApplier: TorrentSessionSettingsApplying {
    public init() {}

    public func apply(_ settings: TorrentSessionSettings) async throws {}
}
