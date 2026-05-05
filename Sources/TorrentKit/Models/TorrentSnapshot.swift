import Foundation

public struct TorrentID: RawRepresentable, Identifiable, Hashable, Codable, Sendable {
    public let rawValue: String

    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct TorrentSnapshot: Identifiable, Hashable, Sendable {
    public let id: TorrentID
    public var name: String
    public var progress: Double
    public var state: TorrentState
    public var sizeBytes: Int64
    public var downloadRateBytesPerSecond: Int64
    public var uploadRateBytesPerSecond: Int64
    public var ratio: Double
    public var eta: TimeInterval?
    public var savePath: String?
    public var category: String
    public var tags: Set<String>
    public var trackers: [TrackerSnapshot]
    public var files: [TorrentFileSnapshot]
    public var peers: [PeerSnapshot]
    public var webSeeds: [WebSeedSnapshot]
    public var pieceAvailability: PieceAvailabilitySnapshot?
    public var limits: TorrentLimitsSnapshot
    public var queue: TorrentQueueSnapshot
    public var shareRules: TorrentShareRuleSnapshot
    public var resumeData: Data?

    public var completedBytes: Int64 {
        guard progress.isFinite, originalSizeBytes > 0 else {
            return 0
        }

        return Int64((Double(originalSizeBytes) * displayProgress).rounded())
    }

    public var remainingBytes: Int64 {
        max(0, originalSizeBytes - completedBytes)
    }

    public var originalSizeBytes: Int64 {
        if sizeBytes > 0 {
            return sizeBytes
        }

        return files.reduce(Int64(0)) { total, file in
            total + max(0, file.sizeBytes)
        }
    }

    public var displayProgress: Double {
        isDone ? 1 : normalizedProgress
    }

    public var isDone: Bool {
        state == .stoppedUploading || normalizedProgress >= 1 || filesAreComplete
    }

    public var isErrored: Bool {
        state.isErrored
    }

    public var stateSortName: String {
        state.displayName
    }

    public var etaSortValue: TimeInterval {
        eta ?? .greatestFiniteMagnitude
    }

    public var queueSortValue: Int {
        queue.position ?? .max
    }

    public var isRunning: Bool {
        state.isStopped == false
    }

    public var hasTransferActivity: Bool {
        downloadRateBytesPerSecond > 0 || uploadRateBytesPerSecond > 0
    }

    private var normalizedProgress: Double {
        guard progress.isFinite else {
            return 0
        }

        return min(max(progress, 0), 1)
    }

    private var filesAreComplete: Bool {
        files.isEmpty == false && files.allSatisfy { file in
            guard file.progress.isFinite else {
                return false
            }

            return file.progress >= 1
        }
    }

    public init(
        id: TorrentID,
        name: String,
        progress: Double,
        state: TorrentState,
        sizeBytes: Int64,
        downloadRateBytesPerSecond: Int64,
        uploadRateBytesPerSecond: Int64,
        ratio: Double,
        eta: TimeInterval?,
        savePath: String? = nil,
        category: String,
        tags: Set<String>,
        trackers: [TrackerSnapshot],
        files: [TorrentFileSnapshot] = [],
        peers: [PeerSnapshot] = [],
        webSeeds: [WebSeedSnapshot] = [],
        pieceAvailability: PieceAvailabilitySnapshot? = nil,
        limits: TorrentLimitsSnapshot = .unlimited,
        queue: TorrentQueueSnapshot = .none,
        shareRules: TorrentShareRuleSnapshot = .defaults,
        resumeData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.progress = progress
        self.state = state
        self.sizeBytes = sizeBytes
        self.downloadRateBytesPerSecond = downloadRateBytesPerSecond
        self.uploadRateBytesPerSecond = uploadRateBytesPerSecond
        self.ratio = ratio
        self.eta = eta
        self.savePath = savePath
        self.category = category
        self.tags = tags
        self.trackers = trackers
        self.files = files
        self.peers = peers
        self.webSeeds = webSeeds
        self.pieceAvailability = pieceAvailability
        self.limits = limits
        self.queue = queue
        self.shareRules = shareRules
        self.resumeData = resumeData
    }

    public static let previewTorrents = [
        TorrentSnapshot(
            id: TorrentID(rawValue: "ubuntu-2404"),
            name: "Ubuntu 24.04 Desktop",
            progress: 0.74,
            state: .downloading,
            sizeBytes: 5_800_000_000,
            downloadRateBytesPerSecond: 2_400_000,
            uploadRateBytesPerSecond: 128_000,
            ratio: 0.42,
            eta: 630,
            savePath: "/Users/example/Downloads",
            category: "Linux",
            tags: ["iso", "test"],
            trackers: [
                TrackerSnapshot(url: "https://tracker.example.org/announce", tier: 0, status: .working, message: nil, seeds: 120, peers: 42, leeches: 18)
            ],
            files: [
                TorrentFileSnapshot(path: "ubuntu-24.04-desktop-amd64.iso", sizeBytes: 5_800_000_000, progress: 0.74, priority: .normal)
            ],
            peers: [
                PeerSnapshot(address: "203.0.113.10:51413", client: "qBittorrent", progress: 0.91, downloadRateBytesPerSecond: 420_000, uploadRateBytesPerSecond: 0, flags: "I", countryCode: "US")
            ],
            webSeeds: [
                WebSeedSnapshot(url: "https://releases.ubuntu.example/ubuntu.iso", status: .working, message: nil)
            ],
            pieceAvailability: PieceAvailabilitySnapshot(totalPieces: 1_024, availablePieces: 812, distributedCopies: 8.4),
            limits: TorrentLimitsSnapshot(downloadLimitBytesPerSecond: nil, uploadLimitBytesPerSecond: 1_000_000),
            queue: TorrentQueueSnapshot(position: 1, isForcedStart: false),
            shareRules: TorrentShareRuleSnapshot(ratioLimit: 2, seedingTimeLimit: 86_400, stopCondition: .pause)
        ),
        TorrentSnapshot(
            id: TorrentID(rawValue: "archlinux-current"),
            name: "Arch Linux Current",
            progress: 1,
            state: .uploading,
            sizeBytes: 1_120_000_000,
            downloadRateBytesPerSecond: 0,
            uploadRateBytesPerSecond: 820_000,
            ratio: 2.84,
            eta: nil,
            savePath: "/Users/example/Downloads",
            category: "Linux",
            tags: ["iso"],
            trackers: [
                TrackerSnapshot(url: "https://tracker.archlinux.org/announce", tier: 0, status: .working, message: nil, seeds: 250, peers: 80, leeches: 20)
            ],
            files: [
                TorrentFileSnapshot(path: "archlinux-current-x86_64.iso", sizeBytes: 1_120_000_000, progress: 1, priority: .high)
            ],
            peers: [
                PeerSnapshot(address: "198.51.100.7:6881", client: "Transmission", progress: 1, downloadRateBytesPerSecond: 0, uploadRateBytesPerSecond: 120_000, flags: "E", countryCode: "DE")
            ],
            pieceAvailability: PieceAvailabilitySnapshot(totalPieces: 512, availablePieces: 512, distributedCopies: 15.2),
            limits: .unlimited,
            queue: TorrentQueueSnapshot(position: 2, isForcedStart: false),
            shareRules: TorrentShareRuleSnapshot(ratioLimit: nil, seedingTimeLimit: nil, stopCondition: .none)
        )
    ]
}

public struct TorrentFileSnapshot: Identifiable, Hashable, Sendable, Codable {
    public var path: String
    public var sizeBytes: Int64
    public var progress: Double
    public var priority: TorrentContentPriority

    public var id: String { path }

    public init(path: String, sizeBytes: Int64, progress: Double, priority: TorrentContentPriority) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.progress = progress
        self.priority = priority
    }
}

public enum TorrentContentPriority: String, Hashable, Sendable, Codable {
    case doNotDownload
    case low
    case normal
    case high
    case maximum

    public var displayName: String {
        switch self {
        case .doNotDownload:
            "Do not download"
        case .low:
            "Low"
        case .normal:
            "Normal"
        case .high:
            "High"
        case .maximum:
            "Maximum"
        }
    }
}

public struct PeerSnapshot: Identifiable, Hashable, Sendable, Codable {
    public var address: String
    public var client: String
    public var progress: Double
    public var downloadRateBytesPerSecond: Int64
    public var uploadRateBytesPerSecond: Int64
    public var flags: String
    public var countryCode: String?

    public var id: String { address }

    public init(
        address: String,
        client: String,
        progress: Double,
        downloadRateBytesPerSecond: Int64,
        uploadRateBytesPerSecond: Int64,
        flags: String,
        countryCode: String?
    ) {
        self.address = address
        self.client = client
        self.progress = progress
        self.downloadRateBytesPerSecond = downloadRateBytesPerSecond
        self.uploadRateBytesPerSecond = uploadRateBytesPerSecond
        self.flags = flags
        self.countryCode = countryCode
    }
}

public struct WebSeedSnapshot: Identifiable, Hashable, Sendable, Codable {
    public var url: String
    public var status: TrackerStatus
    public var message: String?

    public var id: String { url }

    public init(url: String, status: TrackerStatus, message: String?) {
        self.url = url
        self.status = status
        self.message = message
    }
}

public struct PieceAvailabilitySnapshot: Hashable, Sendable, Codable {
    public var totalPieces: Int
    public var availablePieces: Int
    public var distributedCopies: Double

    public var availabilityRatio: Double {
        guard totalPieces > 0 else {
            return 0
        }

        return min(max(Double(availablePieces) / Double(totalPieces), 0), 1)
    }

    public init(totalPieces: Int, availablePieces: Int, distributedCopies: Double) {
        self.totalPieces = totalPieces
        self.availablePieces = availablePieces
        self.distributedCopies = distributedCopies
    }
}

public struct TorrentLimitsSnapshot: Hashable, Sendable, Codable {
    public var downloadLimitBytesPerSecond: Int64?
    public var uploadLimitBytesPerSecond: Int64?

    public init(downloadLimitBytesPerSecond: Int64?, uploadLimitBytesPerSecond: Int64?) {
        self.downloadLimitBytesPerSecond = downloadLimitBytesPerSecond
        self.uploadLimitBytesPerSecond = uploadLimitBytesPerSecond
    }

    public static let unlimited = TorrentLimitsSnapshot(
        downloadLimitBytesPerSecond: nil,
        uploadLimitBytesPerSecond: nil
    )
}

public struct TorrentQueueSnapshot: Hashable, Sendable, Codable {
    public var position: Int?
    public var isForcedStart: Bool

    public init(position: Int?, isForcedStart: Bool) {
        self.position = position
        self.isForcedStart = isForcedStart
    }

    public static let none = TorrentQueueSnapshot(position: nil, isForcedStart: false)
}

public struct TorrentShareRuleSnapshot: Hashable, Sendable, Codable {
    public var ratioLimit: Double?
    public var seedingTimeLimit: TimeInterval?
    public var stopCondition: TorrentStopCondition

    public init(ratioLimit: Double?, seedingTimeLimit: TimeInterval?, stopCondition: TorrentStopCondition) {
        self.ratioLimit = ratioLimit
        self.seedingTimeLimit = seedingTimeLimit
        self.stopCondition = stopCondition
    }

    public static let defaults = TorrentShareRuleSnapshot(
        ratioLimit: nil,
        seedingTimeLimit: nil,
        stopCondition: .none
    )
}

public enum TorrentStopCondition: String, CaseIterable, Hashable, Sendable, Codable {
    case none
    case pause
    case remove

    public var displayName: String {
        switch self {
        case .none:
            "None"
        case .pause:
            "Pause torrent"
        case .remove:
            "Remove torrent"
        }
    }
}

public struct TrackerSnapshot: Hashable, Sendable, Codable {
    public var url: String
    public var tier: Int
    public var status: TrackerStatus
    public var message: String?
    public var seeds: Int
    public var peers: Int
    public var leeches: Int

    public init(
        url: String,
        tier: Int,
        status: TrackerStatus,
        message: String?,
        seeds: Int,
        peers: Int,
        leeches: Int
    ) {
        self.url = url
        self.tier = tier
        self.status = status
        self.message = message
        self.seeds = seeds
        self.peers = peers
        self.leeches = leeches
    }
}

public enum TrackerStatus: String, Hashable, Sendable, Codable {
    case disabled
    case notContacted
    case working
    case updating
    case warning
    case error
}
