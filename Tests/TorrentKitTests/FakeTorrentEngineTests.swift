import Foundation
import Testing
@testable import TorrentKit

struct FakeTorrentEngineTests {
    @Test func addMagnetCreatesDeterministicSnapshot() async throws {
        let engine = FakeTorrentEngine()
        let expectedID = TorrentID(rawValue: "btih:0123456789abcdef0123456789abcdef01234567")

        let snapshot = try await engine.addMagnet(
            AddMagnetRequest(
                magnetURI: ubuntuMagnet,
                category: "Linux",
                tags: ["iso", "fixture"],
                startImmediately: false
            )
        )
        let storedSnapshot = try await engine.snapshot(for: expectedID)
        let snapshots = await engine.snapshots()

        #expect(snapshot.id == expectedID)
        #expect(snapshot.name == "Ubuntu Fake")
        #expect(snapshot.category == "Linux")
        #expect(snapshot.tags == ["iso", "fixture"])
        #expect(snapshot.state == .stoppedDownloading)
        #expect(snapshot.trackers.map(\.url) == ["https://tracker.example/announce"])
        #expect(storedSnapshot == snapshot)
        #expect(snapshots == [snapshot])
    }

    @Test func duplicateMagnetIsRejectedByInfoHash() async throws {
        let engine = FakeTorrentEngine()
        let stream = await engine.events()
        var iterator = stream.makeAsyncIterator()
        let firstSnapshot = try await engine.addMagnet(AddMagnetRequest(magnetURI: ubuntuMagnet))
        var caughtError: TorrentEngineError?

        do {
            _ = try await engine.addMagnet(AddMagnetRequest(magnetURI: ubuntuMagnetWithDifferentName))
        } catch let error as TorrentEngineError {
            caughtError = error
        } catch {
            caughtError = nil
        }

        let addedEvent = await iterator.next()
        let rejectedEvent = await iterator.next()
        let snapshots = await engine.snapshots()

        #expect(addedEvent == .added(firstSnapshot))
        #expect(caughtError == .rejected(.duplicate(firstSnapshot.id)))
        #expect(rejectedEvent == .rejected(.duplicate(firstSnapshot.id)))
        #expect(snapshots == [firstSnapshot])
    }

    @Test func commandsPublishDeterministicEvents() async throws {
        let engine = FakeTorrentEngine()
        let stream = await engine.events()
        var iterator = stream.makeAsyncIterator()
        let addedSnapshot = try await engine.addMagnet(
            AddMagnetRequest(magnetURI: ubuntuMagnet, startImmediately: false)
        )

        try await engine.startTorrent(id: addedSnapshot.id)
        try await engine.stopTorrent(id: addedSnapshot.id)
        try await engine.removeTorrent(id: addedSnapshot.id, deletingFiles: true)

        let addedEvent = await iterator.next()
        let startedEvent = await iterator.next()
        let stoppedEvent = await iterator.next()
        let removedEvent = await iterator.next()
        let remainingSnapshots = await engine.snapshots()

        var startedSnapshot: TorrentSnapshot?
        if case let .started(snapshot)? = startedEvent {
            startedSnapshot = snapshot
        }

        var stoppedSnapshot: TorrentSnapshot?
        if case let .stopped(snapshot)? = stoppedEvent {
            stoppedSnapshot = snapshot
        }

        #expect(addedEvent == .added(addedSnapshot))
        #expect(startedSnapshot?.id == addedSnapshot.id)
        #expect(startedSnapshot?.state == .downloading)
        #expect(startedSnapshot?.downloadRateBytesPerSecond == 1_024_000)
        #expect(stoppedSnapshot?.id == addedSnapshot.id)
        #expect(stoppedSnapshot?.state == .stoppedDownloading)
        #expect(stoppedSnapshot?.downloadRateBytesPerSecond == 0)
        #expect(removedEvent == .removed(addedSnapshot.id, deletingFiles: true))
        #expect(remainingSnapshots.isEmpty)
    }

    @Test func workflowCommandsUpdateSnapshotsAndPublishEvents() async throws {
        let torrentID = TorrentID(rawValue: "btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        let engine = FakeTorrentEngine(initialSnapshots: [
            TorrentSnapshot(
                id: torrentID,
                name: "Original",
                progress: 0.5,
                state: .downloading,
                sizeBytes: 1_000,
                downloadRateBytesPerSecond: 512,
                uploadRateBytesPerSecond: 128,
                ratio: 0.25,
                eta: 60,
                savePath: "/Downloads",
                category: "Linux",
                tags: ["iso"],
                trackers: [
                    TrackerSnapshot(
                        url: "https://tracker.example/announce",
                        tier: 0,
                        status: .working,
                        message: nil,
                        seeds: 10,
                        peers: 4,
                        leeches: 2
                    )
                ]
            )
        ])
        let stream = await engine.events()
        var iterator = stream.makeAsyncIterator()

        let renamed = try await engine.renameTorrent(id: torrentID, to: "Renamed")
        let relocated = try await engine.setTorrentLocation(
            id: torrentID,
            to: URL(fileURLWithPath: "/Volumes/Media", isDirectory: true)
        )
        let rechecking = try await engine.forceRecheckTorrent(id: torrentID)
        let reannouncing = try await engine.forceReannounceTorrent(id: torrentID)
        let forced = try await engine.forceStartTorrent(id: torrentID)
        let limited = try await engine.setTorrentLimits(
            id: torrentID,
            limits: TorrentLimitsSnapshot(downloadLimitBytesPerSecond: 1_024, uploadLimitBytesPerSecond: 2_048)
        )
        let shareLimited = try await engine.setTorrentShareRules(
            id: torrentID,
            shareRules: TorrentShareRuleSnapshot(ratioLimit: 2.5, seedingTimeLimit: 3_600, stopCondition: .pause)
        )
        let storedSnapshot = try await engine.snapshot(for: torrentID)
        let renamedEvent = await iterator.next()
        let relocatedEvent = await iterator.next()
        let recheckingEvent = await iterator.next()
        let reannouncingEvent = await iterator.next()
        let forcedEvent = await iterator.next()
        let limitedEvent = await iterator.next()
        let shareLimitedEvent = await iterator.next()

        #expect(renamed.name == "Renamed")
        #expect(relocated.savePath == "/Volumes/Media")
        #expect(rechecking.state == .checkingDownloading)
        #expect(rechecking.downloadRateBytesPerSecond == 0)
        #expect(rechecking.uploadRateBytesPerSecond == 0)
        #expect(reannouncing.trackers.first?.status == .updating)
        #expect(forced.state == .forcedDownloading)
        #expect(forced.queue.isForcedStart)
        #expect(limited.limits.downloadLimitBytesPerSecond == 1_024)
        #expect(limited.limits.uploadLimitBytesPerSecond == 2_048)
        #expect(shareLimited.shareRules.ratioLimit == 2.5)
        #expect(shareLimited.shareRules.seedingTimeLimit == 3_600)
        #expect(shareLimited.shareRules.stopCondition == .pause)
        #expect(storedSnapshot == shareLimited)
        #expect(renamedEvent == .updated(renamed))
        #expect(relocatedEvent == .updated(relocated))
        #expect(recheckingEvent == .updated(rechecking))
        #expect(reannouncingEvent == .updated(reannouncing))
        #expect(forcedEvent == .started(forced))
        #expect(limitedEvent == .updated(limited))
        #expect(shareLimitedEvent == .updated(shareLimited))
    }

    @Test func queueMovementRenumbersSnapshotsAndPublishesUpdates() async throws {
        let firstID = TorrentID(rawValue: "btih:1111111111111111111111111111111111111111")
        let secondID = TorrentID(rawValue: "btih:2222222222222222222222222222222222222222")
        let thirdID = TorrentID(rawValue: "btih:3333333333333333333333333333333333333333")
        let engine = FakeTorrentEngine(initialSnapshots: [
            queuedSnapshot(id: firstID, name: "First", position: 1),
            queuedSnapshot(id: secondID, name: "Second", position: 2),
            queuedSnapshot(id: thirdID, name: "Third", position: 3)
        ])
        let stream = await engine.events()
        var iterator = stream.makeAsyncIterator()

        let moved = try await engine.moveTorrentInQueue(id: secondID, move: .top)
        let snapshots = await engine.snapshots()
        let firstEvent = await iterator.next()
        let secondEvent = await iterator.next()
        let thirdEvent = await iterator.next()

        #expect(moved.id == secondID)
        #expect(moved.queue.position == 1)
        #expect(snapshots.map(\.id) == [secondID, firstID, thirdID])
        #expect(snapshots.map { $0.queue.position } == [1, 2, 3])
        #expect(firstEvent == .updated(snapshots[0]))
        #expect(secondEvent == .updated(snapshots[1]))
        #expect(thirdEvent == .updated(snapshots[2]))
    }

    @Test(.timeLimit(.minutes(1)))
    func eventStreamIterationEndsWhenConsumerTaskIsCancelled() async {
        let engine = FakeTorrentEngine()
        let stream = await engine.events()
        let initialSubscriberCount = await engine.activeEventStreamCount()
        let task = Task<TorrentEngineEvent?, Never> {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        await Task.yield()
        task.cancel()

        let event = await task.value
        let finalSubscriberCount = await waitForEventStreamCleanup(engine)

        #expect(initialSubscriberCount == 1)
        #expect(event == nil)
        #expect(finalSubscriberCount == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func finishEventStreamsClosesExistingAndFutureStreams() async {
        let engine = FakeTorrentEngine()
        let stream = await engine.events()
        var iterator = stream.makeAsyncIterator()

        await engine.finishEventStreams()

        let finishedEvent = await iterator.next()
        let futureStream = await engine.events()
        var futureIterator = futureStream.makeAsyncIterator()
        let futureEvent = await futureIterator.next()
        let subscriberCount = await engine.activeEventStreamCount()

        #expect(finishedEvent == nil)
        #expect(futureEvent == nil)
        #expect(subscriberCount == 0)
    }

    private var ubuntuMagnet: String {
        "magnet:?xt=urn:btih:0123456789ABCDEF0123456789ABCDEF01234567&dn=Ubuntu%20Fake&tr=https%3A%2F%2Ftracker.example%2Fannounce"
    }

    private var ubuntuMagnetWithDifferentName: String {
        "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Duplicate%20Name"
    }

    private func queuedSnapshot(id: TorrentID, name: String, position: Int) -> TorrentSnapshot {
        TorrentSnapshot(
            id: id,
            name: name,
            progress: 0,
            state: .stoppedDownloading,
            sizeBytes: 0,
            downloadRateBytesPerSecond: 0,
            uploadRateBytesPerSecond: 0,
            ratio: 0,
            eta: nil,
            category: "",
            tags: [],
            trackers: [],
            queue: TorrentQueueSnapshot(position: position, isForcedStart: false)
        )
    }

    private func waitForEventStreamCleanup(_ engine: FakeTorrentEngine) async -> Int {
        for _ in 0..<10 {
            let count = await engine.activeEventStreamCount()
            if count == 0 {
                return count
            }

            await Task.yield()
        }

        return await engine.activeEventStreamCount()
    }
}
