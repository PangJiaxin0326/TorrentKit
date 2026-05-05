import Foundation

public protocol TorrentEngineServicing: Sendable {
    func addMagnet(_ request: AddMagnetRequest) async throws -> TorrentSnapshot
    func addTorrentFile(_ request: AddTorrentFileEngineRequest) async throws -> TorrentSnapshot
    func startTorrent(id: TorrentID) async throws
    func forceStartTorrent(id: TorrentID) async throws -> TorrentSnapshot
    func stopTorrent(id: TorrentID) async throws
    func removeTorrent(id: TorrentID, deletingFiles: Bool) async throws
    func renameTorrent(id: TorrentID, to name: String) async throws -> TorrentSnapshot
    func setTorrentLocation(id: TorrentID, to directory: URL) async throws -> TorrentSnapshot
    func forceRecheckTorrent(id: TorrentID) async throws -> TorrentSnapshot
    func forceReannounceTorrent(id: TorrentID) async throws -> TorrentSnapshot
    func moveTorrentInQueue(id: TorrentID, move: TorrentQueueMove) async throws -> TorrentSnapshot
    func setTorrentLimits(id: TorrentID, limits: TorrentLimitsSnapshot) async throws -> TorrentSnapshot
    func setTorrentShareRules(id: TorrentID, shareRules: TorrentShareRuleSnapshot) async throws -> TorrentSnapshot
    func snapshot(for id: TorrentID) async throws -> TorrentSnapshot
    func snapshots() async -> [TorrentSnapshot]
    func refreshSnapshots() async throws -> [TorrentSnapshot]
    func events() async -> AsyncStream<TorrentEngineEvent>
}

public struct AddMagnetRequest: Hashable, Sendable {
    public var magnetURI: String
    public var saveDirectory: URL
    public var displayName: String?
    public var category: String
    public var tags: Set<String>
    public var startImmediately: Bool
    public var resumeData: Data?

    public init(
        magnetURI: String,
        saveDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory()),
        displayName: String? = nil,
        category: String = "",
        tags: Set<String> = [],
        startImmediately: Bool = true,
        resumeData: Data? = nil
    ) {
        self.magnetURI = magnetURI
        self.saveDirectory = saveDirectory
        self.displayName = displayName
        self.category = category
        self.tags = tags
        self.startImmediately = startImmediately
        self.resumeData = resumeData
    }
}

public struct AddTorrentFileEngineRequest: Hashable, Sendable {
    public var fileURL: URL
    public var saveDirectory: URL
    public var displayName: String?
    public var category: String
    public var tags: Set<String>
    public var startImmediately: Bool
    public var resumeData: Data?

    public init(
        fileURL: URL,
        saveDirectory: URL,
        displayName: String? = nil,
        category: String = "",
        tags: Set<String> = [],
        startImmediately: Bool = true,
        resumeData: Data? = nil
    ) {
        self.fileURL = fileURL
        self.saveDirectory = saveDirectory
        self.displayName = displayName
        self.category = category
        self.tags = tags
        self.startImmediately = startImmediately
        self.resumeData = resumeData
    }
}

public enum TorrentEngineEvent: Equatable, Sendable {
    case added(TorrentSnapshot)
    case started(TorrentSnapshot)
    case stopped(TorrentSnapshot)
    case updated(TorrentSnapshot)
    case removed(TorrentID, deletingFiles: Bool)
    case rejected(TorrentEngineRejection)
}

public enum TorrentEngineRejection: Equatable, Sendable {
    case duplicate(TorrentID)
    case invalidMagnet(String)
    case missingTorrent(TorrentID)
}

public enum TorrentEngineError: Error, Equatable, Sendable {
    case rejected(TorrentEngineRejection)
    case unimplemented
}

public struct UnimplementedTorrentEngine: TorrentEngineServicing {
    public init() {}

    public func addMagnet(_ request: AddMagnetRequest) async throws -> TorrentSnapshot {
        throw TorrentEngineError.unimplemented
    }

    public func addTorrentFile(_ request: AddTorrentFileEngineRequest) async throws -> TorrentSnapshot {
        throw TorrentEngineError.unimplemented
    }

    public func startTorrent(id: TorrentID) async throws {
        throw TorrentEngineError.unimplemented
    }

    public func forceStartTorrent(id: TorrentID) async throws -> TorrentSnapshot {
        throw TorrentEngineError.unimplemented
    }

    public func stopTorrent(id: TorrentID) async throws {
        throw TorrentEngineError.unimplemented
    }

    public func removeTorrent(id: TorrentID, deletingFiles: Bool) async throws {
        throw TorrentEngineError.unimplemented
    }

    public func renameTorrent(id: TorrentID, to name: String) async throws -> TorrentSnapshot {
        throw TorrentEngineError.unimplemented
    }

    public func setTorrentLocation(id: TorrentID, to directory: URL) async throws -> TorrentSnapshot {
        throw TorrentEngineError.unimplemented
    }

    public func forceRecheckTorrent(id: TorrentID) async throws -> TorrentSnapshot {
        throw TorrentEngineError.unimplemented
    }

    public func forceReannounceTorrent(id: TorrentID) async throws -> TorrentSnapshot {
        throw TorrentEngineError.unimplemented
    }

    public func moveTorrentInQueue(id: TorrentID, move: TorrentQueueMove) async throws -> TorrentSnapshot {
        throw TorrentEngineError.unimplemented
    }

    public func setTorrentLimits(id: TorrentID, limits: TorrentLimitsSnapshot) async throws -> TorrentSnapshot {
        throw TorrentEngineError.unimplemented
    }

    public func setTorrentShareRules(id: TorrentID, shareRules: TorrentShareRuleSnapshot) async throws -> TorrentSnapshot {
        throw TorrentEngineError.unimplemented
    }

    public func snapshot(for id: TorrentID) async throws -> TorrentSnapshot {
        throw TorrentEngineError.rejected(.missingTorrent(id))
    }

    public func snapshots() async -> [TorrentSnapshot] {
        []
    }

    public func refreshSnapshots() async throws -> [TorrentSnapshot] {
        []
    }

    public func events() async -> AsyncStream<TorrentEngineEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: TorrentEngineEvent.self)
        continuation.finish()
        return stream
    }
}
