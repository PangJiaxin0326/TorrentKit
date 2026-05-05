import Foundation

public actor FakeTorrentEngine: TorrentEngineServicing {
    private var torrentOrder: [TorrentID] = []
    private var torrentsByID: [TorrentID: TorrentSnapshot] = [:]
    private var continuations: [UUID: AsyncStream<TorrentEngineEvent>.Continuation] = [:]
    private var streamsAreFinished = false

    public init(initialSnapshots: [TorrentSnapshot] = []) {
        for snapshot in initialSnapshots where torrentsByID[snapshot.id] == nil {
            torrentOrder.append(snapshot.id)
            torrentsByID[snapshot.id] = snapshot
        }
    }

    public func addMagnet(_ request: AddMagnetRequest) async throws -> TorrentSnapshot {
        let magnet: ParsedMagnet

        do {
            magnet = try ParsedMagnet(uri: request.magnetURI)
        } catch let error as TorrentEngineError {
            if case let .rejected(rejection) = error {
                publish(.rejected(rejection))
            }

            throw error
        }

        let id = TorrentID(rawValue: "btih:\(magnet.infoHash)")

        guard torrentsByID[id] == nil else {
            try reject(.duplicate(id))
        }

        let snapshot = TorrentSnapshot(
            id: id,
            name: nonEmpty(request.displayName) ?? nonEmpty(magnet.displayName) ?? "Magnet \(magnet.infoHash.prefix(8))",
            progress: 0,
            state: request.startImmediately ? .downloadingMetadata : .stoppedDownloading,
            sizeBytes: 0,
            downloadRateBytesPerSecond: 0,
            uploadRateBytesPerSecond: 0,
            ratio: 0,
            eta: nil,
            category: request.category,
            tags: request.tags,
            trackers: magnet.trackers.enumerated().map { index, tracker in
                TrackerSnapshot(
                    url: tracker,
                    tier: index,
                    status: .notContacted,
                    message: nil,
                    seeds: 0,
                    peers: 0,
                    leeches: 0
                )
            }
        )

        torrentOrder.append(id)
        torrentsByID[id] = snapshot
        publish(.added(snapshot))

        return snapshot
    }

    public func addTorrentFile(_ request: AddTorrentFileEngineRequest) async throws -> TorrentSnapshot {
        let id = TorrentID(rawValue: "file:\(request.fileURL.standardizedFileURL.path.lowercased())")

        guard torrentsByID[id] == nil else {
            try reject(.duplicate(id))
        }

        let snapshot = TorrentSnapshot(
            id: id,
            name: request.displayName ?? request.fileURL.deletingPathExtension().lastPathComponent,
            progress: 0,
            state: request.startImmediately ? .downloadingMetadata : .stoppedDownloading,
            sizeBytes: 0,
            downloadRateBytesPerSecond: 0,
            uploadRateBytesPerSecond: 0,
            ratio: 0,
            eta: nil,
            savePath: request.saveDirectory.path,
            category: request.category,
            tags: request.tags,
            trackers: []
        )

        torrentOrder.append(id)
        torrentsByID[id] = snapshot
        publish(.added(snapshot))

        return snapshot
    }

    public func startTorrent(id: TorrentID) async throws {
        var snapshot = try requireSnapshot(for: id)
        snapshot.state = snapshot.progress >= 1 ? .uploading : .downloading
        snapshot.downloadRateBytesPerSecond = snapshot.progress >= 1 ? 0 : 1_024_000
        snapshot.uploadRateBytesPerSecond = snapshot.progress >= 1 ? 256_000 : 0
        snapshot.queue.isForcedStart = false
        torrentsByID[id] = snapshot
        publish(.started(snapshot))
    }

    public func forceStartTorrent(id: TorrentID) async throws -> TorrentSnapshot {
        var snapshot = try requireSnapshot(for: id)
        snapshot.state = forcedStartState(for: snapshot)
        snapshot.downloadRateBytesPerSecond = snapshot.progress >= 1 ? 0 : 1_024_000
        snapshot.uploadRateBytesPerSecond = snapshot.progress >= 1 ? 256_000 : 0
        snapshot.queue.isForcedStart = true
        torrentsByID[id] = snapshot
        publish(.started(snapshot))
        return snapshot
    }

    public func stopTorrent(id: TorrentID) async throws {
        var snapshot = try requireSnapshot(for: id)
        snapshot.state = snapshot.progress >= 1 ? .stoppedUploading : .stoppedDownloading
        snapshot.downloadRateBytesPerSecond = 0
        snapshot.uploadRateBytesPerSecond = 0
        snapshot.queue.isForcedStart = false
        torrentsByID[id] = snapshot
        publish(.stopped(snapshot))
    }

    public func removeTorrent(id: TorrentID, deletingFiles: Bool) async throws {
        guard torrentsByID.removeValue(forKey: id) != nil else {
            try reject(.missingTorrent(id))
        }

        torrentOrder.removeAll { $0 == id }
        publish(.removed(id, deletingFiles: deletingFiles))
    }

    public func renameTorrent(id: TorrentID, to name: String) async throws -> TorrentSnapshot {
        try updateSnapshot(id: id) { snapshot in
            snapshot.name = name
        }
    }

    public func setTorrentLocation(id: TorrentID, to directory: URL) async throws -> TorrentSnapshot {
        try updateSnapshot(id: id) { snapshot in
            snapshot.savePath = directory.path
        }
    }

    public func forceRecheckTorrent(id: TorrentID) async throws -> TorrentSnapshot {
        try updateSnapshot(id: id) { snapshot in
            snapshot.state = snapshot.progress >= 1 ? .checkingUploading : .checkingDownloading
            snapshot.downloadRateBytesPerSecond = 0
            snapshot.uploadRateBytesPerSecond = 0
        }
    }

    public func forceReannounceTorrent(id: TorrentID) async throws -> TorrentSnapshot {
        try updateSnapshot(id: id) { snapshot in
            snapshot.trackers = snapshot.trackers.map { tracker in
                TrackerSnapshot(
                    url: tracker.url,
                    tier: tracker.tier,
                    status: .updating,
                    message: tracker.message,
                    seeds: tracker.seeds,
                    peers: tracker.peers,
                    leeches: tracker.leeches
                )
            }
        }
    }

    public func moveTorrentInQueue(id: TorrentID, move: TorrentQueueMove) async throws -> TorrentSnapshot {
        _ = try requireSnapshot(for: id)
        guard let currentIndex = torrentOrder.firstIndex(of: id) else {
            try reject(.missingTorrent(id))
        }

        switch move {
        case .top:
            torrentOrder.remove(at: currentIndex)
            torrentOrder.insert(id, at: torrentOrder.startIndex)
        case .up:
            guard currentIndex > torrentOrder.startIndex else {
                break
            }
            torrentOrder.swapAt(currentIndex, torrentOrder.index(before: currentIndex))
        case .down:
            let lastIndex = torrentOrder.index(before: torrentOrder.endIndex)
            guard currentIndex < lastIndex else {
                break
            }
            torrentOrder.swapAt(currentIndex, torrentOrder.index(after: currentIndex))
        case .bottom:
            torrentOrder.remove(at: currentIndex)
            torrentOrder.append(id)
        }

        renumberQueuePositions()
        return try requireSnapshot(for: id)
    }

    public func setTorrentLimits(id: TorrentID, limits: TorrentLimitsSnapshot) async throws -> TorrentSnapshot {
        try updateSnapshot(id: id) { snapshot in
            snapshot.limits = limits
        }
    }

    public func setTorrentShareRules(id: TorrentID, shareRules: TorrentShareRuleSnapshot) async throws -> TorrentSnapshot {
        try updateSnapshot(id: id) { snapshot in
            snapshot.shareRules = shareRules
        }
    }

    public func snapshot(for id: TorrentID) async throws -> TorrentSnapshot {
        try requireSnapshot(for: id)
    }

    public func snapshots() async -> [TorrentSnapshot] {
        torrentOrder.compactMap { torrentsByID[$0] }
    }

    public func refreshSnapshots() async throws -> [TorrentSnapshot] {
        torrentOrder.compactMap { torrentsByID[$0] }
    }

    public func events() async -> AsyncStream<TorrentEngineEvent> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: TorrentEngineEvent.self,
            bufferingPolicy: .bufferingNewest(100)
        )

        guard streamsAreFinished == false else {
            continuation.finish()
            return stream
        }

        let subscriptionID = UUID()
        continuations[subscriptionID] = continuation
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeContinuation(subscriptionID)
            }
        }

        return stream
    }

    public func finishEventStreams() {
        guard streamsAreFinished == false else {
            return
        }

        streamsAreFinished = true
        let activeContinuations = Array(continuations.values)
        continuations.removeAll()

        for continuation in activeContinuations {
            continuation.finish()
        }
    }

    public func activeEventStreamCount() -> Int {
        continuations.count
    }

    private func requireSnapshot(for id: TorrentID) throws -> TorrentSnapshot {
        guard let snapshot = torrentsByID[id] else {
            try reject(.missingTorrent(id))
        }

        return snapshot
    }

    @discardableResult
    private func updateSnapshot(id: TorrentID, _ body: (inout TorrentSnapshot) -> Void) throws -> TorrentSnapshot {
        var snapshot = try requireSnapshot(for: id)
        body(&snapshot)
        torrentsByID[id] = snapshot
        publish(.updated(snapshot))
        return snapshot
    }

    private func renumberQueuePositions() {
        for (index, id) in torrentOrder.enumerated() {
            guard var snapshot = torrentsByID[id] else {
                continue
            }

            snapshot.queue = TorrentQueueSnapshot(
                position: index + 1,
                isForcedStart: snapshot.queue.isForcedStart
            )
            torrentsByID[id] = snapshot
            publish(.updated(snapshot))
        }
    }

    private func reject(_ rejection: TorrentEngineRejection) throws -> Never {
        publish(.rejected(rejection))
        throw TorrentEngineError.rejected(rejection)
    }

    private func publish(_ event: TorrentEngineEvent) {
        guard streamsAreFinished == false else {
            return
        }

        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func forcedStartState(for snapshot: TorrentSnapshot) -> TorrentState {
        if snapshot.progress >= 1 {
            return .forcedUploading
        }
        if snapshot.sizeBytes == 0 || snapshot.state == .downloadingMetadata || snapshot.state == .forcedDownloadingMetadata {
            return .forcedDownloadingMetadata
        }
        return .forcedDownloading
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        return value
    }
}

private struct ParsedMagnet {
    public let infoHash: String
    public let displayName: String?
    public let trackers: [String]

    public init(uri: String) throws {
        guard
            let components = URLComponents(string: uri),
            components.scheme?.lowercased() == "magnet"
        else {
            throw TorrentEngineError.rejected(.invalidMagnet("Magnet URI must use the magnet scheme."))
        }

        let queryItems = components.queryItems ?? []

        guard let exactTopic = queryItems.first(where: { $0.name == "xt" })?.value else {
            throw TorrentEngineError.rejected(.invalidMagnet("Magnet URI is missing an exact topic."))
        }

        let prefix = "urn:btih:"
        guard exactTopic.lowercased().hasPrefix(prefix) else {
            throw TorrentEngineError.rejected(.invalidMagnet("Magnet exact topic must be a BitTorrent info hash."))
        }

        let infoHash = String(exactTopic.dropFirst(prefix.count)).lowercased()
        guard infoHash.isEmpty == false else {
            throw TorrentEngineError.rejected(.invalidMagnet("Magnet info hash cannot be empty."))
        }

        self.infoHash = infoHash
        displayName = queryItems.first(where: { $0.name == "dn" })?.value
        trackers = queryItems.filter { $0.name == "tr" }.compactMap(\.value)
    }
}
