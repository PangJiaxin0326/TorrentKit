import Foundation
import TorrentKit

struct LibtorrentFileEvent: Decodable, Equatable, Sendable {
    var path: String
    var sizeBytes: Int64
    var completedBytes: Int64?
    var progress: Double?
    var priority: String?

    private enum CodingKeys: String, CodingKey {
        case path
        case sizeBytes = "size_bytes"
        case completedBytes = "completed_bytes"
        case progress
        case priority
    }
}

struct LibtorrentDownloadEvent: Decodable, Equatable, Sendable {
    enum EventKind: String, Decodable, Sendable {
        case alert
        case dhtBootstrap = "dht_bootstrap"
        case dhtReply = "dht_reply"
        case externalIP = "external_ip"
        case finished
        case listenFailed = "listen_failed"
        case listenSucceeded = "listen_succeeded"
        case metadataComplete = "metadata_complete"
        case metadataReceived = "metadata_received"
        case paused
        case peerConnected = "peer_connected"
        case peerDisconnected = "peer_disconnected"
        case portMapFailed = "portmap_failed"
        case portMapSucceeded = "portmap_succeeded"
        case resumed
        case removed
        case sessionActive = "session_active"
        case selfTestFinished = "self_test_finished"
        case selfTestStarted = "self_test_started"
        case started
        case status
        case timeout
        case trackerAnnounce = "tracker_announce"
        case trackerError = "tracker_error"
        case trackerReply = "tracker_reply"
    }

    var event: EventKind
    var name: String?
    var progress: Double?
    var downloadRate: Int?
    var uploadRate: Int?
    var totalDone: Int64?
    var totalWanted: Int64?
    var numPeers: Int?
    var numSeeds: Int?
    var state: String?
    var isSeed: Bool?
    var isPaused: Bool?
    var isAutoManaged: Bool?
    var isForcedStart: Bool?
    var hasMetadata: Bool?
    var savePath: String?
    var root: String?
    var magnet: String?
    var infoHash: String?
    var peer: String?
    var file: String?
    var sha256: String?
    var message: String?
    var endpoint: String?
    var port: Int?
    var externalPort: Int?
    var listenInterface: String?
    var listenInterfaces: String?
    var outgoingInterfaces: String?
    var trackerURL: String?
    var direction: String?
    var externalAddress: String?
    var files: [LibtorrentFileEvent]
    var pieceCount: Int?
    var availablePieces: Int?
    var distributedCopies: Double?
    var downloadLimit: Int?
    var uploadLimit: Int?
    var queuePosition: Int?
    var maximumConnections: Int?
    var resumeData: Data?

    init(
        event: EventKind,
        name: String? = nil,
        progress: Double? = nil,
        downloadRate: Int? = nil,
        uploadRate: Int? = nil,
        totalDone: Int64? = nil,
        totalWanted: Int64? = nil,
        numPeers: Int? = nil,
        numSeeds: Int? = nil,
        state: String? = nil,
        isSeed: Bool? = nil,
        isPaused: Bool? = nil,
        isAutoManaged: Bool? = nil,
        isForcedStart: Bool? = nil,
        hasMetadata: Bool? = nil,
        savePath: String? = nil,
        root: String? = nil,
        magnet: String? = nil,
        infoHash: String? = nil,
        peer: String? = nil,
        file: String? = nil,
        sha256: String? = nil,
        message: String? = nil,
        endpoint: String? = nil,
        port: Int? = nil,
        externalPort: Int? = nil,
        listenInterface: String? = nil,
        listenInterfaces: String? = nil,
        outgoingInterfaces: String? = nil,
        trackerURL: String? = nil,
        direction: String? = nil,
        externalAddress: String? = nil,
        files: [LibtorrentFileEvent] = [],
        pieceCount: Int? = nil,
        availablePieces: Int? = nil,
        distributedCopies: Double? = nil,
        downloadLimit: Int? = nil,
        uploadLimit: Int? = nil,
        queuePosition: Int? = nil,
        maximumConnections: Int? = nil,
        resumeData: Data? = nil
    ) {
        self.event = event
        self.name = name
        self.progress = progress
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.totalDone = totalDone
        self.totalWanted = totalWanted
        self.numPeers = numPeers
        self.numSeeds = numSeeds
        self.state = state
        self.isSeed = isSeed
        self.isPaused = isPaused
        self.isAutoManaged = isAutoManaged
        self.isForcedStart = isForcedStart
        self.hasMetadata = hasMetadata
        self.savePath = savePath
        self.root = root
        self.magnet = magnet
        self.infoHash = infoHash
        self.peer = peer
        self.file = file
        self.sha256 = sha256
        self.message = message
        self.endpoint = endpoint
        self.port = port
        self.externalPort = externalPort
        self.listenInterface = listenInterface
        self.listenInterfaces = listenInterfaces
        self.outgoingInterfaces = outgoingInterfaces
        self.trackerURL = trackerURL
        self.direction = direction
        self.externalAddress = externalAddress
        self.files = files
        self.pieceCount = pieceCount
        self.availablePieces = availablePieces
        self.distributedCopies = distributedCopies
        self.downloadLimit = downloadLimit
        self.uploadLimit = uploadLimit
        self.queuePosition = queuePosition
        self.maximumConnections = maximumConnections
        self.resumeData = resumeData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(EventKind.self, forKey: .event)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        downloadRate = try container.decodeIfPresent(Int.self, forKey: .downloadRate)
        uploadRate = try container.decodeIfPresent(Int.self, forKey: .uploadRate)
        totalDone = try container.decodeIfPresent(Int64.self, forKey: .totalDone)
        totalWanted = try container.decodeIfPresent(Int64.self, forKey: .totalWanted)
        numPeers = try container.decodeIfPresent(Int.self, forKey: .numPeers)
        numSeeds = try container.decodeIfPresent(Int.self, forKey: .numSeeds)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        isSeed = try container.decodeIfPresent(Bool.self, forKey: .isSeed)
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused)
        isAutoManaged = try container.decodeIfPresent(Bool.self, forKey: .isAutoManaged)
        isForcedStart = try container.decodeIfPresent(Bool.self, forKey: .isForcedStart)
        hasMetadata = try container.decodeIfPresent(Bool.self, forKey: .hasMetadata)
        savePath = try container.decodeIfPresent(String.self, forKey: .savePath)
        root = try container.decodeIfPresent(String.self, forKey: .root)
        magnet = try container.decodeIfPresent(String.self, forKey: .magnet)
        infoHash = try container.decodeIfPresent(String.self, forKey: .infoHash)
        peer = try container.decodeIfPresent(String.self, forKey: .peer)
        file = try container.decodeIfPresent(String.self, forKey: .file)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        port = try container.decodeIfPresent(Int.self, forKey: .port)
        externalPort = try container.decodeIfPresent(Int.self, forKey: .externalPort)
        listenInterface = try container.decodeIfPresent(String.self, forKey: .listenInterface)
        listenInterfaces = try container.decodeIfPresent(String.self, forKey: .listenInterfaces)
        outgoingInterfaces = try container.decodeIfPresent(String.self, forKey: .outgoingInterfaces)
        trackerURL = try container.decodeIfPresent(String.self, forKey: .trackerURL)
        direction = try container.decodeIfPresent(String.self, forKey: .direction)
        externalAddress = try container.decodeIfPresent(String.self, forKey: .externalAddress)
        files = try container.decodeIfPresent([LibtorrentFileEvent].self, forKey: .files) ?? []
        pieceCount = try container.decodeIfPresent(Int.self, forKey: .pieceCount)
        availablePieces = try container.decodeIfPresent(Int.self, forKey: .availablePieces)
        distributedCopies = try container.decodeIfPresent(Double.self, forKey: .distributedCopies)
        downloadLimit = try container.decodeIfPresent(Int.self, forKey: .downloadLimit)
        uploadLimit = try container.decodeIfPresent(Int.self, forKey: .uploadLimit)
        queuePosition = try container.decodeIfPresent(Int.self, forKey: .queuePosition)
        maximumConnections = try container.decodeIfPresent(Int.self, forKey: .maximumConnections)
        if let encodedResumeData = try container.decodeIfPresent(String.self, forKey: .resumeData) {
            resumeData = Data(base64Encoded: encodedResumeData)
        } else {
            resumeData = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case event
        case name
        case progress
        case downloadRate = "download_rate"
        case uploadRate = "upload_rate"
        case totalDone = "total_done"
        case totalWanted = "total_wanted"
        case numPeers = "num_peers"
        case numSeeds = "num_seeds"
        case state
        case isSeed = "is_seed"
        case isPaused = "is_paused"
        case isAutoManaged = "is_auto_managed"
        case isForcedStart = "is_forced_start"
        case hasMetadata = "has_metadata"
        case savePath = "save_path"
        case root
        case magnet
        case infoHash = "info_hash"
        case peer
        case file
        case sha256
        case message
        case endpoint
        case port
        case externalPort = "external_port"
        case listenInterface = "listen_interface"
        case listenInterfaces = "listen_interfaces"
        case outgoingInterfaces = "outgoing_interfaces"
        case trackerURL = "tracker_url"
        case direction
        case externalAddress = "external_address"
        case files
        case pieceCount = "piece_count"
        case availablePieces = "available_pieces"
        case distributedCopies = "distributed_copies"
        case downloadLimit = "download_limit"
        case uploadLimit = "upload_limit"
        case queuePosition = "queue_position"
        case maximumConnections = "max_connections"
        case resumeData = "resume_data"
    }
}

struct LibtorrentBridgeSessionSettings: Equatable, Sendable {
    var allowIncomingConnections: Bool
    var listenPort: Int
    var enablePortMapping: Bool
    var maximumConnections: Int
    var maximumConnectionsPerTorrent: Int
    var downloadLimitBytesPerSecond: Int
    var uploadLimitBytesPerSecond: Int
    var enableDHT: Bool
    var enableLocalServiceDiscovery: Bool
    var enablePeerExchange: Bool
    var limitUTPRate: Bool
    var includeProtocolOverhead: Bool
    var limitLocalPeerRates: Bool
    var proxyKind: String
    var proxyHost: String
    var proxyPort: Int
    var proxyPeerConnections: Bool
    var proxyHostnames: Bool
    var connectionSpeed: Int
    var requestQueueSize: Int
    var dhtBootstrapNodes: String
}

protocol LibtorrentSessionSettingsBridging: Sendable {
    func apply(_ settings: LibtorrentBridgeSessionSettings) throws
}

struct NativeLibtorrentSessionSettingsBridge: LibtorrentSessionSettingsBridging {
    func apply(_ settings: LibtorrentBridgeSessionSettings) throws {
        let bridge = LibtorrentNativeBridge()
        try bridge.applySessionSettings(
            allowIncomingConnections: settings.allowIncomingConnections,
            listenPort: settings.listenPort,
            enablePortMapping: settings.enablePortMapping,
            maximumConnections: settings.maximumConnections,
            maximumConnectionsPerTorrent: settings.maximumConnectionsPerTorrent,
            downloadLimitBytesPerSecond: settings.downloadLimitBytesPerSecond,
            uploadLimitBytesPerSecond: settings.uploadLimitBytesPerSecond,
            enableDHT: settings.enableDHT,
            enableLocalServiceDiscovery: settings.enableLocalServiceDiscovery,
            enablePeerExchange: settings.enablePeerExchange,
            limitUTPRate: settings.limitUTPRate,
            includeProtocolOverhead: settings.includeProtocolOverhead,
            limitLocalPeerRates: settings.limitLocalPeerRates,
            proxyKind: settings.proxyKind,
            proxyHost: settings.proxyHost,
            proxyPort: settings.proxyPort,
            proxyPeerConnections: settings.proxyPeerConnections,
            proxyHostnames: settings.proxyHostnames,
            connectionSpeed: settings.connectionSpeed,
            requestQueueSize: settings.requestQueueSize,
            dhtBootstrapNodes: settings.dhtBootstrapNodes
        )
    }
}

struct LibtorrentDownloader: Sendable {
    private let sessionSettingsBridge: any LibtorrentSessionSettingsBridging

    init(sessionSettingsBridge: any LibtorrentSessionSettingsBridging = NativeLibtorrentSessionSettingsBridge()) {
        self.sessionSettingsBridge = sessionSettingsBridge
    }

    enum DownloaderError: Error, Equatable, CustomStringConvertible {
        case bridgeFailed(String)
        case duplicateTorrent
        case missingTorrent
        case undecodablePayload(String)

        var description: String {
            switch self {
            case let .bridgeFailed(message):
                "libtorrent bridge failed: \(message)"
            case .duplicateTorrent:
                "libtorrent bridge rejected a duplicate torrent."
            case .missingTorrent:
                "libtorrent bridge could not find the active torrent."
            case let .undecodablePayload(payload):
                "libtorrent bridge produced an undecodable payload: \(payload)"
            }
        }
    }

    func downloadMagnet(
        _ magnet: String,
        savePath: URL,
        timeout: TimeInterval = 120,
        metadataOnly: Bool = false,
        startImmediately: Bool = true,
        resumeData: Data? = nil,
        peer: String? = nil
    ) throws -> [LibtorrentDownloadEvent] {
        let bridge = LibtorrentNativeBridge()

        do {
            let payloads = try bridge.downloadMagnet(
                magnet,
                savePath: savePath,
                resumeData: resumeData,
                timeout: timeout,
                metadataOnly: metadataOnly,
                startImmediately: startImmediately,
                peer: peer
            )
            return try payloads.map(Self.decodeEvent)
        } catch let error as DownloaderError {
            throw error
        } catch {
            throw Self.bridgeError(error)
        }
    }

    func downloadTorrentFile(
        _ torrentFile: URL,
        savePath: URL,
        timeout: TimeInterval = 120,
        startImmediately: Bool = true,
        resumeData: Data? = nil
    ) throws -> [LibtorrentDownloadEvent] {
        let bridge = LibtorrentNativeBridge()

        do {
            let payloads = try bridge.downloadTorrentFile(
                torrentFile,
                savePath: savePath,
                resumeData: resumeData,
                timeout: timeout,
                startImmediately: startImmediately
            )
            return try payloads.map(Self.decodeEvent)
        } catch let error as DownloaderError {
            throw error
        } catch {
            throw Self.bridgeError(error)
        }
    }

    func activeTorrentStatuses() throws -> [LibtorrentDownloadEvent] {
        let bridge = LibtorrentNativeBridge()

        do {
            let payloads = try bridge.activeTorrentStatuses()
            return try payloads.map(Self.decodeEvent)
        } catch let error as DownloaderError {
            throw error
        } catch {
            throw Self.bridgeError(error)
        }
    }

    func startTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        let bridge = LibtorrentNativeBridge()

        do {
            let payloads = try bridge.startTorrent(infoHash: infoHash)
            return try payloads.map(Self.decodeEvent)
        } catch let error as DownloaderError {
            throw error
        } catch {
            throw Self.bridgeError(error)
        }
    }

    func pauseTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        let bridge = LibtorrentNativeBridge()

        do {
            let payloads = try bridge.pauseTorrent(infoHash: infoHash)
            return try payloads.map(Self.decodeEvent)
        } catch let error as DownloaderError {
            throw error
        } catch {
            throw Self.bridgeError(error)
        }
    }

    func removeTorrent(infoHash: String, deletingFiles: Bool) throws -> [LibtorrentDownloadEvent] {
        let bridge = LibtorrentNativeBridge()

        do {
            let payloads = try bridge.removeTorrent(infoHash: infoHash, deletingFiles: deletingFiles)
            return try payloads.map(Self.decodeEvent)
        } catch let error as DownloaderError {
            throw error
        } catch {
            throw Self.bridgeError(error)
        }
    }

    func forceStartTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        let bridge = LibtorrentNativeBridge()

        do {
            let payloads = try bridge.forceStartTorrent(infoHash: infoHash)
            return try payloads.map(Self.decodeEvent)
        } catch let error as DownloaderError {
            throw error
        } catch {
            throw Self.bridgeError(error)
        }
    }

    func moveTorrent(infoHash: String, queueMove: TorrentQueueMove) throws -> [LibtorrentDownloadEvent] {
        let bridge = LibtorrentNativeBridge()

        do {
            let payloads = try bridge.moveTorrent(infoHash: infoHash, queueMove: queueMove.rawValue)
            return try payloads.map(Self.decodeEvent)
        } catch let error as DownloaderError {
            throw error
        } catch {
            throw Self.bridgeError(error)
        }
    }

    func setTorrentLimits(
        infoHash: String,
        downloadLimitBytesPerSecond: Int64?,
        uploadLimitBytesPerSecond: Int64?
    ) throws -> [LibtorrentDownloadEvent] {
        let bridge = LibtorrentNativeBridge()

        do {
            let payloads = try bridge.setTorrentLimits(
                infoHash: infoHash,
                downloadLimitBytesPerSecond: Self.bridgeLimit(downloadLimitBytesPerSecond),
                uploadLimitBytesPerSecond: Self.bridgeLimit(uploadLimitBytesPerSecond)
            )
            return try payloads.map(Self.decodeEvent)
        } catch let error as DownloaderError {
            throw error
        } catch {
            throw Self.bridgeError(error)
        }
    }

    func applySessionSettings(_ settings: TorrentSessionSettings) throws {
        do {
            try sessionSettingsBridge.apply(Self.bridgeSessionSettings(from: settings))
        } catch let error as DownloaderError {
            throw error
        } catch {
            throw Self.bridgeError(error)
        }
    }

    func runSelfTest(root: URL, timeout: TimeInterval = 60) throws -> [LibtorrentDownloadEvent] {
        let bridge = LibtorrentNativeBridge()

        do {
            let payloads = try bridge.runSelfTest(root: root, timeout: timeout)
            return try payloads.map(Self.decodeEvent)
        } catch let error as DownloaderError {
            throw error
        } catch {
            throw Self.bridgeError(error)
        }
    }

    static func bridgeError(_ error: any Error) -> DownloaderError {
        if let bridgeError = error as? LibtorrentBridgeError {
            switch bridgeError.code {
            case .missingTorrent:
                return .missingTorrent
            case .addTorrentFailed where bridgeError.message.localizedCaseInsensitiveContains("duplicate"):
                return .duplicateTorrent
            default:
                return .bridgeFailed(bridgeError.message)
            }
        }

        return .bridgeFailed(error.localizedDescription)
    }

    private static func decodeEvent(_ payload: [String: Any]) throws -> LibtorrentDownloadEvent {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            return try JSONDecoder().decode(LibtorrentDownloadEvent.self, from: data)
        } catch {
            throw DownloaderError.undecodablePayload(String(describing: payload))
        }
    }

    private static func bridgeLimit(_ limit: Int64?) -> Int {
        guard let limit, limit > 0 else {
            return 0
        }

        return Int(min(limit, Int64(Int32.max)))
    }

    private static func bridgeSessionSettings(from settings: TorrentSessionSettings) -> LibtorrentBridgeSessionSettings {
        let proxy = settings.proxy
        let bridgeProxyKind = Self.bridgeProxyKind(from: proxy)
        let speedLimits = bridgeSpeedLimits(from: settings.speed)

        return LibtorrentBridgeSessionSettings(
            allowIncomingConnections: settings.connection.allowIncomingConnections,
            listenPort: bridgeListenPort(from: settings.connection),
            enablePortMapping: settings.connection.allowIncomingConnections && settings.connection.portMappingEnabled,
            maximumConnections: positiveOrUnlimited(settings.connection.maximumConnections),
            maximumConnectionsPerTorrent: positiveOrUnlimited(settings.connection.maximumConnectionsPerTorrent),
            downloadLimitBytesPerSecond: bridgePositiveInt(speedLimits.download),
            uploadLimitBytesPerSecond: bridgePositiveInt(speedLimits.upload),
            enableDHT: settings.bitTorrent.isDHTEnabled,
            enableLocalServiceDiscovery: settings.bitTorrent.isLSDEnabled,
            enablePeerExchange: settings.bitTorrent.isPeXEnabled,
            limitUTPRate: settings.speed.limitUTPRate,
            includeProtocolOverhead: settings.speed.includeProtocolOverhead,
            limitLocalPeerRates: settings.speed.limitLocalPeerRates,
            proxyKind: bridgeProxyKind.rawValue,
            proxyHost: bridgeProxyHost(from: proxy, kind: bridgeProxyKind),
            proxyPort: bridgeProxyPort(from: proxy, kind: bridgeProxyKind),
            proxyPeerConnections: bridgeProxyKind != .none && proxy.proxyPeerConnections,
            proxyHostnames: bridgeProxyKind != .none,
            connectionSpeed: positiveOrDefault(
                settings.advanced.connectionSpeed,
                defaultValue: AdvancedLibtorrentSettings.defaults.connectionSpeed
            ),
            requestQueueSize: positiveOrDefault(
                settings.advanced.requestQueueSize,
                defaultValue: AdvancedLibtorrentSettings.defaults.requestQueueSize
            ),
            dhtBootstrapNodes: bridgeDHTBootstrapNodes(settings.advanced.dhtBootstrapNodes)
        )
    }

    private static func bridgeListenPort(from settings: TorrentConnectionSettings) -> Int {
        guard settings.allowIncomingConnections else {
            return 0
        }
        guard (1...65_535).contains(settings.listenPort) else {
            return TorrentConnectionSettings.defaults.listenPort
        }

        return settings.listenPort
    }

    private static func bridgeSpeedLimits(from settings: TorrentSessionSpeedSettings) -> (download: Int, upload: Int) {
        if settings.isAlternativeLimitEnabled || scheduleIsActive(settings.scheduler) {
            return (
                download: settings.alternativeDownloadLimitBytesPerSecond,
                upload: settings.alternativeUploadLimitBytesPerSecond
            )
        }

        return (
            download: settings.downloadLimitBytesPerSecond,
            upload: settings.uploadLimitBytesPerSecond
        )
    }

    private static func scheduleIsActive(_ schedule: SpeedSchedulerPreferences, date: Date = Date(), calendar: Calendar = .current) -> Bool {
        SpeedSchedulerEvaluator(calendar: calendar).isAlternativeLimitTime(scheduler: schedule, at: date)
    }

    private static func bridgeProxyKind(from settings: TorrentProxySettings) -> TorrentProxyKind {
        guard settings.useForBitTorrent, settings.kind != .none else {
            return .none
        }
        guard settings.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              (1...65_535).contains(settings.port) else {
            return .none
        }
        return settings.kind
    }

    private static func bridgeProxyHost(from settings: TorrentProxySettings, kind: TorrentProxyKind) -> String {
        kind == .none ? "" : settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bridgeProxyPort(from settings: TorrentProxySettings, kind: TorrentProxyKind) -> Int {
        kind == .none ? 0 : settings.port
    }

    private static func bridgeDHTBootstrapNodes(_ value: String) -> String {
        let nodes = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return nodes.isEmpty ? AdvancedLibtorrentSettings.defaultDHTBootstrapNodes : nodes
    }

    private static func bridgePositiveInt(_ value: Int) -> Int {
        guard value > 0 else {
            return 0
        }

        return min(value, Int(Int32.max))
    }

    private static func positiveOrUnlimited(_ value: Int) -> Int {
        guard value > 0 else {
            return -1
        }

        return min(value, Int(Int32.max))
    }

    private static func positiveOrDefault(_ value: Int, defaultValue: Int) -> Int {
        guard value > 0 else {
            return defaultValue
        }

        return min(value, Int(Int32.max))
    }
}
