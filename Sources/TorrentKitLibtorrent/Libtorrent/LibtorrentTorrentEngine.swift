import Foundation
import TorrentKit

protocol LibtorrentDownloading: Sendable {
    func downloadMagnet(
        _ magnet: String,
        savePath: URL,
        timeout: TimeInterval,
        metadataOnly: Bool,
        startImmediately: Bool,
        resumeData: Data?,
        peer: String?
    ) throws -> [LibtorrentDownloadEvent]
    func downloadTorrentFile(
        _ torrentFile: URL,
        savePath: URL,
        timeout: TimeInterval,
        startImmediately: Bool,
        resumeData: Data?
    ) throws -> [LibtorrentDownloadEvent]
    func activeTorrentStatuses() throws -> [LibtorrentDownloadEvent]
    func startTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent]
    func pauseTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent]
    func removeTorrent(infoHash: String, deletingFiles: Bool) throws -> [LibtorrentDownloadEvent]
    func forceStartTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent]
    func moveTorrent(infoHash: String, queueMove: TorrentQueueMove) throws -> [LibtorrentDownloadEvent]
    func setTorrentLimits(
        infoHash: String,
        downloadLimitBytesPerSecond: Int64?,
        uploadLimitBytesPerSecond: Int64?
    ) throws -> [LibtorrentDownloadEvent]
    func applySessionSettings(_ settings: TorrentSessionSettings) throws
}

extension LibtorrentDownloader: LibtorrentDownloading {}

public actor LibtorrentTorrentEngine: TorrentEngineServicing, TorrentSessionSettingsApplying {
    private let downloader: any LibtorrentDownloading
    private var torrentOrder: [TorrentID] = []
    private var torrentsByID: [TorrentID: TorrentSnapshot] = [:]
    private var removedTorrentIDs = Set<TorrentID>()
    private var continuations: [UUID: AsyncStream<TorrentEngineEvent>.Continuation] = [:]
    private var streamsAreFinished = false

    public init() {
        self.downloader = LibtorrentDownloader()
    }

    init(downloader: any LibtorrentDownloading) {
        self.downloader = downloader
    }

    public func addMagnet(_ request: AddMagnetRequest) async throws -> TorrentSnapshot {
        let downloader = downloader
        let events: [LibtorrentDownloadEvent]
        do {
            events = try await Task.detached {
                try downloader.downloadMagnet(
                    request.magnetURI,
                    savePath: request.saveDirectory,
                    timeout: 120,
                    metadataOnly: false,
                    startImmediately: request.startImmediately,
                    resumeData: request.resumeData,
                    peer: nil
                )
            }.value
        } catch {
            throw Self.engineError(
                from: error,
                id: LibtorrentEventMapper.torrentID(fromMagnet: request.magnetURI)
            )
        }
        let snapshot = try storeSnapshot(
            from: events,
            fallback: .magnet(request),
            publishedEvent: TorrentEngineEvent.added,
            storagePolicy: .allowNewOrExisting
        )

        return snapshot
    }

    public func addTorrentFile(_ request: AddTorrentFileEngineRequest) async throws -> TorrentSnapshot {
        let downloader = downloader
        let events: [LibtorrentDownloadEvent]
        do {
            events = try await Task.detached {
                try downloader.downloadTorrentFile(
                    request.fileURL,
                    savePath: request.saveDirectory,
                    timeout: 120,
                    startImmediately: request.startImmediately,
                    resumeData: request.resumeData
                )
            }.value
        } catch {
            throw Self.engineError(
                from: error,
                id: TorrentID(rawValue: "file:\(request.fileURL.standardizedFileURL.path)")
            )
        }
        let snapshot = try storeSnapshot(
            from: events,
            fallback: .file(request),
            publishedEvent: TorrentEngineEvent.added,
            storagePolicy: .allowNewOrExisting
        )

        return snapshot
    }

    public func startTorrent(id: TorrentID) async throws {
        _ = try requireSnapshot(for: id)
        let downloader = downloader
        let events: [LibtorrentDownloadEvent]
        do {
            events = try await Task.detached {
                try downloader.startTorrent(infoHash: id.libtorrentInfoHash)
            }.value
        } catch {
            throw Self.engineError(from: error, id: id)
        }
        _ = try storeSnapshot(
            from: events,
            fallback: .existing(id),
            publishedEvent: TorrentEngineEvent.started,
            storagePolicy: .existingOnly
        )
    }

    public func forceStartTorrent(id: TorrentID) async throws -> TorrentSnapshot {
        _ = try requireSnapshot(for: id)
        let downloader = downloader
        let events: [LibtorrentDownloadEvent]
        do {
            events = try await Task.detached {
                try downloader.forceStartTorrent(infoHash: id.libtorrentInfoHash)
            }.value
        } catch {
            throw Self.engineError(from: error, id: id)
        }

        return try storeSnapshot(
            from: events,
            fallback: .existing(id),
            publishedEvent: TorrentEngineEvent.started,
            storagePolicy: .existingOnly
        ) { snapshot in
            var snapshot = snapshot
            snapshot.state = Self.forcedStartState(for: snapshot)
            snapshot.queue.isForcedStart = true
            return snapshot
        }
    }

    public func stopTorrent(id: TorrentID) async throws {
        _ = try requireSnapshot(for: id)
        let downloader = downloader
        let events: [LibtorrentDownloadEvent]
        do {
            events = try await Task.detached {
                try downloader.pauseTorrent(infoHash: id.libtorrentInfoHash)
            }.value
        } catch {
            throw Self.engineError(from: error, id: id)
        }
        _ = try storeSnapshot(
            from: events,
            fallback: .existing(id),
            publishedEvent: TorrentEngineEvent.stopped,
            storagePolicy: .existingOnly
        )
    }

    public func removeTorrent(id: TorrentID, deletingFiles: Bool) async throws {
        _ = try requireSnapshot(for: id)
        let downloader = downloader
        do {
            _ = try await Task.detached {
                try downloader.removeTorrent(infoHash: id.libtorrentInfoHash, deletingFiles: deletingFiles)
            }.value
        } catch {
            throw Self.engineError(from: error, id: id)
        }

        torrentsByID.removeValue(forKey: id)
        torrentOrder.removeAll { $0 == id }
        removedTorrentIDs.insert(id)
        publish(.removed(id, deletingFiles: deletingFiles))
    }

    public func renameTorrent(id: TorrentID, to name: String) async throws -> TorrentSnapshot {
        _ = try requireSnapshot(for: id)
        throw TorrentEngineError.unimplemented
    }

    public func setTorrentLocation(id: TorrentID, to directory: URL) async throws -> TorrentSnapshot {
        _ = try requireSnapshot(for: id)
        throw TorrentEngineError.unimplemented
    }

    public func forceRecheckTorrent(id: TorrentID) async throws -> TorrentSnapshot {
        _ = try requireSnapshot(for: id)
        throw TorrentEngineError.unimplemented
    }

    public func forceReannounceTorrent(id: TorrentID) async throws -> TorrentSnapshot {
        _ = try requireSnapshot(for: id)
        throw TorrentEngineError.unimplemented
    }

    public func moveTorrentInQueue(id: TorrentID, move: TorrentQueueMove) async throws -> TorrentSnapshot {
        _ = try requireSnapshot(for: id)
        let downloader = downloader
        let events: [LibtorrentDownloadEvent]
        do {
            events = try await Task.detached {
                try downloader.moveTorrent(infoHash: id.libtorrentInfoHash, queueMove: move)
            }.value
        } catch {
            throw Self.engineError(from: error, id: id)
        }

        return try storeSnapshot(
            from: events,
            fallback: .existing(id),
            publishedEvent: TorrentEngineEvent.updated,
            storagePolicy: .existingOnly
        )
    }

    public func setTorrentLimits(id: TorrentID, limits: TorrentLimitsSnapshot) async throws -> TorrentSnapshot {
        _ = try requireSnapshot(for: id)
        let downloader = downloader
        let events: [LibtorrentDownloadEvent]
        do {
            events = try await Task.detached {
                try downloader.setTorrentLimits(
                    infoHash: id.libtorrentInfoHash,
                    downloadLimitBytesPerSecond: limits.downloadLimitBytesPerSecond,
                    uploadLimitBytesPerSecond: limits.uploadLimitBytesPerSecond
                )
            }.value
        } catch {
            throw Self.engineError(from: error, id: id)
        }

        return try storeSnapshot(
            from: events,
            fallback: .existing(id),
            publishedEvent: TorrentEngineEvent.updated,
            storagePolicy: .existingOnly,
            preservingMissingWorkflowState: false
        )
    }

    public func setTorrentShareRules(id: TorrentID, shareRules: TorrentShareRuleSnapshot) async throws -> TorrentSnapshot {
        _ = try requireSnapshot(for: id)
        throw TorrentEngineError.unimplemented
    }

    public func snapshot(for id: TorrentID) async throws -> TorrentSnapshot {
        try requireSnapshot(for: id)
    }

    public func snapshots() async -> [TorrentSnapshot] {
        orderedSnapshots()
    }

    public func refreshSnapshots() async throws -> [TorrentSnapshot] {
        let downloader = downloader
        let events = try await Task.detached {
            try downloader.activeTorrentStatuses()
        }.value
        let snapshots = LibtorrentEventMapper.snapshots(from: events, fallback: nil)

        for snapshot in snapshots where removedTorrentIDs.contains(snapshot.id) == false {
            upsert(snapshot)
        }

        return orderedSnapshots()
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

    public func apply(_ settings: TorrentSessionSettings) async throws {
        let downloader = downloader
        do {
            try await Task.detached {
                try downloader.applySessionSettings(settings)
            }.value
        } catch {
            throw Self.sessionSettingsError(from: error)
        }
    }

    private enum SnapshotStoragePolicy {
        case allowNewOrExisting
        case existingOnly
    }

    private func storeSnapshot(
        from events: [LibtorrentDownloadEvent],
        fallback: LibtorrentEventMapper.Fallback,
        publishedEvent: (TorrentSnapshot) -> TorrentEngineEvent,
        storagePolicy: SnapshotStoragePolicy,
        preservingMissingWorkflowState: Bool = true,
        transform: (TorrentSnapshot) -> TorrentSnapshot = { $0 }
    ) throws -> TorrentSnapshot {
        guard let mappedSnapshot = LibtorrentEventMapper.snapshot(from: events, fallback: fallback) else {
            throw TorrentEngineError.rejected(.invalidMagnet("The torrent engine did not return a torrent identifier."))
        }
        let snapshot = transform(mappedSnapshot)

        switch storagePolicy {
        case .allowNewOrExisting:
            removedTorrentIDs.remove(snapshot.id)
        case .existingOnly:
            guard torrentsByID[snapshot.id] != nil, removedTorrentIDs.contains(snapshot.id) == false else {
                throw TorrentEngineError.rejected(.missingTorrent(snapshot.id))
            }
        }

        upsert(snapshot, preservingMissingWorkflowState: preservingMissingWorkflowState)
        publish(publishedEvent(snapshot))
        return snapshot
    }

    private func upsert(_ snapshot: TorrentSnapshot, preservingMissingWorkflowState: Bool = true) {
        if torrentsByID[snapshot.id] == nil {
            torrentOrder.append(snapshot.id)
        }

        if let existing = torrentsByID[snapshot.id] {
            torrentsByID[snapshot.id] = Self.mergedSnapshot(
                primary: snapshot,
                secondary: existing,
                preservingMissingWorkflowState: preservingMissingWorkflowState
            )
        } else {
            torrentsByID[snapshot.id] = snapshot
        }
    }

    private func requireSnapshot(for id: TorrentID) throws -> TorrentSnapshot {
        guard let snapshot = torrentsByID[id] else {
            publish(.rejected(.missingTorrent(id)))
            throw TorrentEngineError.rejected(.missingTorrent(id))
        }

        return snapshot
    }

    private func orderedSnapshots() -> [TorrentSnapshot] {
        torrentOrder.compactMap { torrentsByID[$0] }
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

    private static func engineError(from error: any Error, id: TorrentID) -> any Error {
        guard let downloaderError = error as? LibtorrentDownloader.DownloaderError else {
            return error
        }

        switch downloaderError {
        case .missingTorrent:
            return TorrentEngineError.rejected(.missingTorrent(id))
        case .duplicateTorrent:
            return TorrentEngineError.rejected(.duplicate(id))
        case .bridgeFailed, .undecodablePayload:
            return error
        }
    }

    private static func sessionSettingsError(from error: any Error) -> any Error {
        guard let downloaderError = error as? LibtorrentDownloader.DownloaderError else {
            return error
        }

        switch downloaderError {
        case .missingTorrent, .duplicateTorrent, .bridgeFailed, .undecodablePayload:
            return downloaderError
        }
    }

    private static func forcedStartState(for snapshot: TorrentSnapshot) -> TorrentState {
        if snapshot.progress >= 1 {
            return .forcedUploading
        }
        if snapshot.sizeBytes == 0 || snapshot.state == .downloadingMetadata || snapshot.state == .forcedDownloadingMetadata {
            return .forcedDownloadingMetadata
        }
        return .forcedDownloading
    }

    private static func mergedSnapshot(primary: TorrentSnapshot, secondary: TorrentSnapshot, preservingMissingWorkflowState: Bool) -> TorrentSnapshot {
        var mergedSnapshot = primary
        mergedSnapshot.savePath = mergedSnapshot.savePath ?? secondary.savePath
        if mergedSnapshot.category.isEmpty {
            mergedSnapshot.category = secondary.category
        }
        if mergedSnapshot.tags.isEmpty {
            mergedSnapshot.tags = secondary.tags
        }
        if mergedSnapshot.trackers.isEmpty {
            mergedSnapshot.trackers = secondary.trackers
        }
        if mergedSnapshot.files.isEmpty {
            mergedSnapshot.files = secondary.files
        }
        if mergedSnapshot.peers.isEmpty {
            mergedSnapshot.peers = secondary.peers
        }
        if mergedSnapshot.webSeeds.isEmpty {
            mergedSnapshot.webSeeds = secondary.webSeeds
        }
        mergedSnapshot.pieceAvailability = mergedSnapshot.pieceAvailability ?? secondary.pieceAvailability
        if preservingMissingWorkflowState, mergedSnapshot.limits == .unlimited {
            mergedSnapshot.limits = secondary.limits
        }
        if preservingMissingWorkflowState, mergedSnapshot.queue == .none, mergedSnapshot.state.isStopped == false {
            mergedSnapshot.queue = secondary.queue
        }
        if preservingMissingWorkflowState, mergedSnapshot.shareRules == .defaults {
            mergedSnapshot.shareRules = secondary.shareRules
        }
        mergedSnapshot.resumeData = mergedSnapshot.resumeData ?? secondary.resumeData
        return mergedSnapshot
    }
}

enum LibtorrentEventMapper {
    enum Fallback {
        case magnet(AddMagnetRequest)
        case file(AddTorrentFileEngineRequest)
        case existing(TorrentID)
    }

    static func snapshot(from events: [LibtorrentDownloadEvent], fallback: Fallback?) -> TorrentSnapshot? {
        guard let finalEvent = events.last(where: { isTransferStatusEvent($0.event) }) else {
            return fallbackSnapshot(fallback)
        }

        guard var snapshot = snapshot(from: finalEvent, fallback: fallback) else {
            return nil
        }

        let trackers = trackerSnapshots(from: events)
        if trackers.isEmpty == false {
            snapshot.trackers = trackers
        }

        let peers = peerSnapshots(from: events)
        if peers.isEmpty == false {
            snapshot.peers = peers
        }

        return snapshot
    }

    static func snapshots(from events: [LibtorrentDownloadEvent], fallback: Fallback?) -> [TorrentSnapshot] {
        events
            .filter { isTransferStatusEvent($0.event) }
            .compactMap { snapshot(from: $0, fallback: fallback) }
    }

    static func snapshot(from event: LibtorrentDownloadEvent, fallback: Fallback?) -> TorrentSnapshot? {
        let fallbackName = displayName(from: fallback)
        let name = event.name ?? fallbackName ?? "Magnet Download"
        guard let identifier = event.infoHash ?? identifier(from: fallback) else {
            return nil
        }

        let eventSizeBytes = max(event.totalWanted ?? 0, event.totalDone ?? 0)
        let mappedProgress = normalizedProgress(event.progress ?? progressFromBytes(totalDone: event.totalDone, totalWanted: event.totalWanted))
        let isComplete = isCompletedTransfer(event, progress: mappedProgress)
        let downloadRate = isComplete || event.isPaused == true ? 0 : Int64(event.downloadRate ?? 0)
        let uploadRate = isComplete || event.isPaused == true ? 0 : Int64(event.uploadRate ?? 0)
        let progress = isComplete ? 1 : mappedProgress
        let eta = isComplete ? nil : eta(totalDone: event.totalDone, totalWanted: event.totalWanted, downloadRate: downloadRate)
        let files = fileSnapshots(from: event, fallbackName: name, sizeBytes: eventSizeBytes, progress: progress)
        let fileSizeBytes = files.reduce(Int64(0)) { total, file in
            total + max(0, file.sizeBytes)
        }
        let sizeBytes = max(eventSizeBytes, fileSizeBytes)

        return TorrentSnapshot(
            id: torrentID(from: identifier),
            name: name,
            progress: progress,
            state: torrentState(from: event),
            sizeBytes: sizeBytes,
            downloadRateBytesPerSecond: downloadRate,
            uploadRateBytesPerSecond: uploadRate,
            ratio: 0,
            eta: eta,
            savePath: event.savePath ?? savePath(from: fallback),
            category: category(from: fallback),
            tags: tags(from: fallback),
            trackers: [],
            files: files,
            peers: peerSnapshots(from: [event]),
            pieceAvailability: pieceAvailability(from: event, sizeBytes: sizeBytes, progress: progress),
            limits: limits(from: event),
            queue: queue(from: event),
            resumeData: event.resumeData
        )
    }

    private static func fallbackSnapshot(_ fallback: Fallback?) -> TorrentSnapshot? {
        guard let fallback else {
            return nil
        }

        switch fallback {
        case let .magnet(request):
            guard let identifier = magnetInfoHash(from: request.magnetURI) else {
                return nil
            }
            return TorrentSnapshot(
                id: torrentID(from: identifier),
                name: request.displayName ?? magnetDisplayName(from: request.magnetURI) ?? "Magnet Download",
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
        case let .file(request):
            return TorrentSnapshot(
                id: TorrentID(rawValue: "file:\(request.fileURL.standardizedFileURL.path)"),
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
        case let .existing(id):
            return TorrentSnapshot(
                id: id,
                name: "Torrent",
                progress: 0,
                state: .unknown,
                sizeBytes: 0,
                downloadRateBytesPerSecond: 0,
                uploadRateBytesPerSecond: 0,
                ratio: 0,
                eta: nil,
                category: "",
                tags: [],
                trackers: []
            )
        }
    }

    private static func displayName(from fallback: Fallback?) -> String? {
        switch fallback {
        case let .magnet(request):
            request.displayName ?? magnetDisplayName(from: request.magnetURI)
        case let .file(request):
            request.displayName ?? request.fileURL.deletingPathExtension().lastPathComponent
        case .existing, .none:
            nil
        }
    }

    private static func trackerSnapshots(from events: [LibtorrentDownloadEvent]) -> [TrackerSnapshot] {
        var trackersByURL: [String: TrackerSnapshot] = [:]
        var order: [String] = []

        for event in events {
            guard let trackerURL = event.trackerURL, trackerURL.isEmpty == false else {
                continue
            }

            if trackersByURL[trackerURL] == nil {
                order.append(trackerURL)
            }

            trackersByURL[trackerURL] = TrackerSnapshot(
                url: trackerURL,
                tier: order.firstIndex(of: trackerURL) ?? 0,
                status: trackerStatus(from: event),
                message: event.message,
                seeds: event.numSeeds ?? 0,
                peers: event.numPeers ?? 0,
                leeches: 0
            )
        }

        return order.compactMap { trackersByURL[$0] }
    }

    private static func trackerStatus(from event: LibtorrentDownloadEvent) -> TrackerStatus {
        switch event.event {
        case .trackerReply:
            .working
        case .trackerAnnounce:
            .updating
        case .trackerError:
            .error
        default:
            .notContacted
        }
    }

    private static func peerSnapshots(from events: [LibtorrentDownloadEvent]) -> [PeerSnapshot] {
        var peersByAddress: [String: PeerSnapshot] = [:]
        var order: [String] = []

        for event in events {
            let address = event.endpoint ?? event.peer
            guard let address, address.isEmpty == false else {
                continue
            }

            if peersByAddress[address] == nil {
                order.append(address)
            }

            peersByAddress[address] = PeerSnapshot(
                address: address,
                client: event.direction.map { "Peer \($0)" } ?? "Peer",
                progress: normalizedProgress(event.progress ?? 0),
                downloadRateBytesPerSecond: Int64(event.downloadRate ?? 0),
                uploadRateBytesPerSecond: Int64(event.uploadRate ?? 0),
                flags: event.event == .peerDisconnected ? "Disconnected" : "Connected",
                countryCode: nil
            )
        }

        return order.compactMap { peersByAddress[$0] }
    }

    private static func fileSnapshots(
        from event: LibtorrentDownloadEvent,
        fallbackName: String,
        sizeBytes: Int64,
        progress: Double
    ) -> [TorrentFileSnapshot] {
        if event.files.isEmpty == false {
            return event.files.map { file in
                let fileProgress = file.progress
                    ?? progressFromBytes(totalDone: file.completedBytes, totalWanted: file.sizeBytes)
                    ?? progress
                return TorrentFileSnapshot(
                    path: file.path,
                    sizeBytes: file.sizeBytes,
                    progress: normalizedProgress(fileProgress),
                    priority: priority(from: file.priority)
                )
            }
        }

        return fileSnapshots(name: fallbackName, sizeBytes: sizeBytes, progress: progress)
    }

    private static func fileSnapshots(name: String, sizeBytes: Int64, progress: Double) -> [TorrentFileSnapshot] {
        guard sizeBytes > 0 else {
            return []
        }

        return [
            TorrentFileSnapshot(
                path: name,
                sizeBytes: sizeBytes,
                progress: progress,
                priority: .normal
            )
        ]
    }

    private static func priority(from value: String?) -> TorrentContentPriority {
        switch value {
        case "do_not_download":
            .doNotDownload
        case "low":
            .low
        case "high":
            .high
        case "maximum":
            .maximum
        default:
            .normal
        }
    }

    private static func pieceAvailability(
        from event: LibtorrentDownloadEvent,
        sizeBytes: Int64,
        progress: Double
    ) -> PieceAvailabilitySnapshot? {
        if let pieceCount = event.pieceCount, pieceCount > 0 {
            return PieceAvailabilitySnapshot(
                totalPieces: pieceCount,
                availablePieces: min(max(event.availablePieces ?? 0, 0), pieceCount),
                distributedCopies: event.distributedCopies ?? normalizedProgress(progress)
            )
        }

        guard sizeBytes > 0 else {
            return nil
        }

        let pieceSize = 4 * 1_024 * 1_024
        let totalPieces = max(1, Int((Double(sizeBytes) / Double(pieceSize)).rounded(.up)))
        let availablePieces = Int((Double(totalPieces) * normalizedProgress(progress)).rounded(.down))
        return PieceAvailabilitySnapshot(
            totalPieces: totalPieces,
            availablePieces: availablePieces,
            distributedCopies: progress >= 1 ? 1 : normalizedProgress(progress)
        )
    }

    private static func limits(from event: LibtorrentDownloadEvent) -> TorrentLimitsSnapshot {
        TorrentLimitsSnapshot(
            downloadLimitBytesPerSecond: positiveLimit(event.downloadLimit),
            uploadLimitBytesPerSecond: positiveLimit(event.uploadLimit)
        )
    }

    private static func positiveLimit(_ limit: Int?) -> Int64? {
        guard let limit, limit > 0 else {
            return nil
        }

        return Int64(limit)
    }

    private static func queue(from event: LibtorrentDownloadEvent) -> TorrentQueueSnapshot {
        let isForcedStart = isForceStarted(event)
        guard let queuePosition = event.queuePosition, queuePosition >= 0 else {
            return TorrentQueueSnapshot(position: nil, isForcedStart: isForcedStart)
        }

        return TorrentQueueSnapshot(position: queuePosition + 1, isForcedStart: isForcedStart)
    }

    private static func identifier(from fallback: Fallback?) -> String? {
        switch fallback {
        case let .magnet(request):
            magnetInfoHash(from: request.magnetURI)
        case let .file(request):
            "file:\(request.fileURL.standardizedFileURL.path)"
        case let .existing(id):
            id.rawValue
        case .none:
            nil
        }
    }

    private static func savePath(from fallback: Fallback?) -> String? {
        switch fallback {
        case let .magnet(request):
            request.saveDirectory.path
        case let .file(request):
            request.saveDirectory.path
        case .existing, .none:
            nil
        }
    }

    private static func category(from fallback: Fallback?) -> String {
        switch fallback {
        case let .magnet(request):
            request.category
        case let .file(request):
            request.category
        case .existing, .none:
            ""
        }
    }

    private static func tags(from fallback: Fallback?) -> Set<String> {
        switch fallback {
        case let .magnet(request):
            request.tags
        case let .file(request):
            request.tags
        case .existing, .none:
            []
        }
    }

    private static func torrentID(from identifier: String) -> TorrentID {
        let lowercased = identifier.lowercased()
        if lowercased.hasPrefix("btih:") || lowercased.hasPrefix("file:") {
            return TorrentID(rawValue: lowercased)
        }

        return TorrentID(rawValue: "btih:\(lowercased)")
    }

    static func torrentID(fromMagnet magnet: String) -> TorrentID {
        guard let infoHash = magnetInfoHash(from: magnet) else {
            return TorrentID(rawValue: "magnet:\(magnet)")
        }

        return torrentID(from: infoHash)
    }

    private static func progressFromBytes(totalDone: Int64?, totalWanted: Int64?) -> Double? {
        guard let totalDone, let totalWanted, totalWanted > 0 else {
            return nil
        }

        return Double(totalDone) / Double(totalWanted)
    }

    private static func normalizedProgress(_ progress: Double?) -> Double {
        guard let progress, progress.isFinite else {
            return 0
        }

        return min(max(progress, 0), 1)
    }

    private static func eta(totalDone: Int64?, totalWanted: Int64?, downloadRate: Int64) -> TimeInterval? {
        guard let totalDone, let totalWanted, totalWanted > totalDone, downloadRate > 0 else {
            return nil
        }

        return TimeInterval(totalWanted - totalDone) / TimeInterval(downloadRate)
    }

    private static func torrentState(from event: LibtorrentDownloadEvent) -> TorrentState {
        let progress = normalizedProgress(event.progress ?? progressFromBytes(totalDone: event.totalDone, totalWanted: event.totalWanted))

        if event.event == .paused || event.isPaused == true {
            return progress >= 1 ? .stoppedUploading : .stoppedDownloading
        }

        let downloadRate = Int64(event.downloadRate ?? 0)
        let uploadRate = Int64(event.uploadRate ?? 0)
        let isComplete = isCompletedTransfer(event, progress: progress)
        if isComplete {
            return .stoppedUploading
        }

        let mappedState: TorrentState
        switch event.state {
        case "downloading_metadata":
            mappedState = .downloadingMetadata
        case "downloading":
            mappedState = downloadRate > 0 ? .downloading : .stalledDownloading
        case "finished", "seeding":
            mappedState = uploadRate > 0 ? .uploading : .stalledUploading
        case "checking_files", "queued_for_checking":
            mappedState = isComplete ? .checkingUploading : .checkingDownloading
        case "checking_resume_data":
            mappedState = .checkingResumeData
        case "allocating":
            mappedState = .moving
        default:
            if event.hasMetadata == false {
                mappedState = .downloadingMetadata
            } else if isComplete {
                mappedState = uploadRate > 0 ? .uploading : .stalledUploading
            } else {
                mappedState = downloadRate > 0 ? .downloading : .stalledDownloading
            }
        }

        return forcedStateIfNeeded(mappedState, event: event, progress: progress)
    }

    private static func isForceStarted(_ event: LibtorrentDownloadEvent) -> Bool {
        if let isForcedStart = event.isForcedStart {
            return isForcedStart && event.isPaused != true
        }

        guard let isAutoManaged = event.isAutoManaged else {
            return false
        }

        return isAutoManaged == false && event.isPaused != true
    }

    private static func forcedStateIfNeeded(_ state: TorrentState, event: LibtorrentDownloadEvent, progress: Double) -> TorrentState {
        guard isForceStarted(event) else {
            return state
        }

        let isComplete = isCompletedTransfer(event, progress: progress)

        if isComplete {
            return .stoppedUploading
        }

        if state == .downloadingMetadata || state == .forcedDownloadingMetadata || event.hasMetadata == false {
            return .forcedDownloadingMetadata
        }

        return .forcedDownloading
    }

    private static func isCompletedTransfer(_ event: LibtorrentDownloadEvent, progress: Double) -> Bool {
        if event.event == .finished {
            return true
        }

        if event.state == "completed" || event.state == "finished" || event.state == "seeding" {
            return true
        }

        if event.isSeed == true || progress >= 1 {
            return true
        }

        guard let totalWanted = event.totalWanted, totalWanted > 0, let totalDone = event.totalDone else {
            return false
        }

        return totalDone >= totalWanted
    }

    private static func isTransferStatusEvent(_ event: LibtorrentDownloadEvent.EventKind) -> Bool {
        switch event {
        case .finished, .metadataComplete, .metadataReceived, .paused, .resumed, .sessionActive, .status:
            true
        case .alert, .dhtBootstrap, .dhtReply, .externalIP, .listenFailed, .listenSucceeded,
                .peerConnected, .peerDisconnected, .portMapFailed, .portMapSucceeded,
                .removed, .selfTestFinished, .selfTestStarted, .started, .timeout, .trackerAnnounce,
                .trackerError, .trackerReply:
            false
        }
    }

    private static func magnetInfoHash(from magnet: String) -> String? {
        guard let components = URLComponents(string: magnet) else {
            return nil
        }

        let exactTopic = components.queryItems?.first { $0.name == "xt" }?.value
        let prefix = "urn:btih:"
        guard let exactTopic, exactTopic.lowercased().hasPrefix(prefix) else {
            return nil
        }

        return String(exactTopic.dropFirst(prefix.count))
    }

    private static func magnetDisplayName(from magnet: String) -> String? {
        URLComponents(string: magnet)?
            .queryItems?
            .first { $0.name == "dn" }?
            .value
    }
}

private extension TorrentID {
    var libtorrentInfoHash: String {
        let prefix = "btih:"
        if rawValue.lowercased().hasPrefix(prefix) {
            return String(rawValue.dropFirst(prefix.count))
        }

        return rawValue
    }
}
