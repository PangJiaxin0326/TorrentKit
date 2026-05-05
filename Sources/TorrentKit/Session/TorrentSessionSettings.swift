import Foundation

public enum TorrentProxyKind: String, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case none
    case http
    case socks5

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none:
            "None"
        case .http:
            "HTTP"
        case .socks5:
            "SOCKS5"
        }
    }
}

public struct SpeedSchedulerPreferences: Equatable, Sendable {
    public var isEnabled: Bool
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var days: SpeedScheduleDays

    public init(
        isEnabled: Bool,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        days: SpeedScheduleDays
    ) {
        self.isEnabled = isEnabled
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.days = days
    }

    public static let defaults = SpeedSchedulerPreferences(
        isEnabled: false,
        startMinuteOfDay: 8 * 60,
        endMinuteOfDay: 20 * 60,
        days: .everyDay
    )
}

public enum SpeedScheduleDays: String, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case everyDay
    case weekdays
    case weekends
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .everyDay:
            "Every day"
        case .weekdays:
            "Weekdays"
        case .weekends:
            "Weekends"
        case .monday:
            "Monday"
        case .tuesday:
            "Tuesday"
        case .wednesday:
            "Wednesday"
        case .thursday:
            "Thursday"
        case .friday:
            "Friday"
        case .saturday:
            "Saturday"
        case .sunday:
            "Sunday"
        }
    }

    public func contains(weekday: Int) -> Bool {
        switch self {
        case .everyDay:
            true
        case .weekdays:
            (2...6).contains(weekday)
        case .weekends:
            weekday == 1 || weekday == 7
        case .monday:
            weekday == 2
        case .tuesday:
            weekday == 3
        case .wednesday:
            weekday == 4
        case .thursday:
            weekday == 5
        case .friday:
            weekday == 6
        case .saturday:
            weekday == 7
        case .sunday:
            weekday == 1
        }
    }
}

public struct TorrentSessionSettings: Equatable, Sendable {
    public var connection: TorrentConnectionSettings
    public var proxy: TorrentProxySettings
    public var speed: TorrentSessionSpeedSettings
    public var bitTorrent: BitTorrentSessionSettings
    public var advanced: AdvancedLibtorrentSettings

    public init(
        connection: TorrentConnectionSettings = .defaults,
        proxy: TorrentProxySettings = .disabled,
        speed: TorrentSessionSpeedSettings = .defaults,
        bitTorrent: BitTorrentSessionSettings = .defaults,
        advanced: AdvancedLibtorrentSettings = .defaults
    ) {
        self.connection = connection
        self.proxy = proxy
        self.speed = speed
        self.bitTorrent = bitTorrent
        self.advanced = advanced
    }

    public static let defaults = TorrentSessionSettings()
}

public struct TorrentConnectionSettings: Equatable, Sendable {
    public var listenPort: Int
    public var portMappingEnabled: Bool
    public var maximumConnections: Int
    public var maximumConnectionsPerTorrent: Int
    public var allowIncomingConnections: Bool

    public init(
        listenPort: Int,
        portMappingEnabled: Bool,
        maximumConnections: Int,
        maximumConnectionsPerTorrent: Int,
        allowIncomingConnections: Bool
    ) {
        self.listenPort = listenPort
        self.portMappingEnabled = portMappingEnabled
        self.maximumConnections = maximumConnections
        self.maximumConnectionsPerTorrent = maximumConnectionsPerTorrent
        self.allowIncomingConnections = allowIncomingConnections
    }

    public static let defaults = TorrentConnectionSettings(
        listenPort: 49_889,
        portMappingEnabled: true,
        maximumConnections: 500,
        maximumConnectionsPerTorrent: 100,
        allowIncomingConnections: true
    )
}

public struct TorrentProxySettings: Equatable, Sendable {
    public var kind: TorrentProxyKind
    public var host: String
    public var port: Int
    public var useForBitTorrent: Bool
    public var useForRSS: Bool
    public var useForGeneralRequests: Bool
    public var proxyPeerConnections: Bool

    public init(
        kind: TorrentProxyKind,
        host: String,
        port: Int,
        useForBitTorrent: Bool,
        useForRSS: Bool,
        useForGeneralRequests: Bool,
        proxyPeerConnections: Bool
    ) {
        self.kind = kind
        self.host = host
        self.port = port
        self.useForBitTorrent = useForBitTorrent
        self.useForRSS = useForRSS
        self.useForGeneralRequests = useForGeneralRequests
        self.proxyPeerConnections = proxyPeerConnections
    }

    public static let disabled = TorrentProxySettings(
        kind: .none,
        host: "",
        port: 0,
        useForBitTorrent: false,
        useForRSS: false,
        useForGeneralRequests: false,
        proxyPeerConnections: false
    )
}

public struct TorrentSessionSpeedSettings: Equatable, Sendable {
    public var downloadLimitBytesPerSecond: Int
    public var uploadLimitBytesPerSecond: Int
    public var alternativeDownloadLimitBytesPerSecond: Int
    public var alternativeUploadLimitBytesPerSecond: Int
    public var isAlternativeLimitEnabled: Bool
    public var scheduler: SpeedSchedulerPreferences
    public var limitUTPRate: Bool
    public var includeProtocolOverhead: Bool
    public var limitLocalPeerRates: Bool

    public init(
        downloadLimitBytesPerSecond: Int,
        uploadLimitBytesPerSecond: Int,
        alternativeDownloadLimitBytesPerSecond: Int,
        alternativeUploadLimitBytesPerSecond: Int,
        isAlternativeLimitEnabled: Bool,
        scheduler: SpeedSchedulerPreferences,
        limitUTPRate: Bool,
        includeProtocolOverhead: Bool,
        limitLocalPeerRates: Bool
    ) {
        self.downloadLimitBytesPerSecond = downloadLimitBytesPerSecond
        self.uploadLimitBytesPerSecond = uploadLimitBytesPerSecond
        self.alternativeDownloadLimitBytesPerSecond = alternativeDownloadLimitBytesPerSecond
        self.alternativeUploadLimitBytesPerSecond = alternativeUploadLimitBytesPerSecond
        self.isAlternativeLimitEnabled = isAlternativeLimitEnabled
        self.scheduler = scheduler
        self.limitUTPRate = limitUTPRate
        self.includeProtocolOverhead = includeProtocolOverhead
        self.limitLocalPeerRates = limitLocalPeerRates
    }

    public static let defaults = TorrentSessionSpeedSettings(
        downloadLimitBytesPerSecond: 0,
        uploadLimitBytesPerSecond: 0,
        alternativeDownloadLimitBytesPerSecond: 10 * 1_024,
        alternativeUploadLimitBytesPerSecond: 10 * 1_024,
        isAlternativeLimitEnabled: false,
        scheduler: .defaults,
        limitUTPRate: true,
        includeProtocolOverhead: false,
        limitLocalPeerRates: true
    )

    public var effectiveDownloadLimitBytesPerSecond: Int {
        isAlternativeLimitEnabled ? alternativeDownloadLimitBytesPerSecond : downloadLimitBytesPerSecond
    }

    public var effectiveUploadLimitBytesPerSecond: Int {
        isAlternativeLimitEnabled ? alternativeUploadLimitBytesPerSecond : uploadLimitBytesPerSecond
    }
}

public struct BitTorrentSessionSettings: Equatable, Sendable {
    public var isDHTEnabled: Bool
    public var isPeXEnabled: Bool
    public var isLSDEnabled: Bool

    public init(
        isDHTEnabled: Bool,
        isPeXEnabled: Bool,
        isLSDEnabled: Bool
    ) {
        self.isDHTEnabled = isDHTEnabled
        self.isPeXEnabled = isPeXEnabled
        self.isLSDEnabled = isLSDEnabled
    }

    public static let defaults = BitTorrentSessionSettings(
        isDHTEnabled: true,
        isPeXEnabled: true,
        isLSDEnabled: true
    )
}

public struct AdvancedLibtorrentSettings: Equatable, Sendable {
    public var connectionSpeed: Int
    public var requestQueueSize: Int
    public var dhtBootstrapNodes: String

    public init(
        connectionSpeed: Int,
        requestQueueSize: Int,
        dhtBootstrapNodes: String
    ) {
        self.connectionSpeed = connectionSpeed
        self.requestQueueSize = requestQueueSize
        self.dhtBootstrapNodes = dhtBootstrapNodes
    }

    public static let defaultDHTBootstrapNodes = "dht.libtorrent.org:25401,dht.transmissionbt.com:6881,router.bittorrent.com:6881"

    public static let defaults = AdvancedLibtorrentSettings(
        connectionSpeed: 30,
        requestQueueSize: 500,
        dhtBootstrapNodes: defaultDHTBootstrapNodes
    )
}
