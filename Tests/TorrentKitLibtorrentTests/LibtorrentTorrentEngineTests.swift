import Foundation
import Testing
@testable import TorrentKit
@testable import TorrentKitLibtorrent

struct LibtorrentTorrentEngineTests {
    @Test func mapperPreservesDownloadingStateParity() throws {
        let snapshot = try #require(LibtorrentEventMapper.snapshot(
            from: LibtorrentDownloadEvent(
                event: .status,
                name: "Zero Rate Download",
                progress: 0.5,
                downloadRate: 0,
                uploadRate: 0,
                totalDone: 500,
                totalWanted: 1_000,
                state: "downloading",
                isSeed: false,
                isPaused: false,
                hasMetadata: true,
                infoHash: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            ),
            fallback: nil
        ))

        #expect(snapshot.id.rawValue == "btih:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        #expect(snapshot.state == .stalledDownloading)
        #expect(snapshot.progress == 0.5)
        #expect(snapshot.sizeBytes == 1_000)
        #expect(snapshot.downloadRateBytesPerSecond == 0)
        #expect(snapshot.eta == nil)
    }

    @Test func mapperPreservesFastResumeData() throws {
        let resumeData = Data("fast-resume".utf8)
        let snapshot = try #require(LibtorrentEventMapper.snapshot(
            from: LibtorrentDownloadEvent(
                event: .status,
                name: "Resumable",
                progress: 0.25,
                downloadRate: 1_024,
                uploadRate: 0,
                totalDone: 250,
                totalWanted: 1_000,
                state: "downloading",
                isSeed: false,
                isPaused: false,
                hasMetadata: true,
                infoHash: "fefefefefefefefefefefefefefefefefefefefe",
                resumeData: resumeData
            ),
            fallback: nil
        ))

        #expect(snapshot.resumeData == resumeData)
    }

    @Test func mapperStopsCompletedSeedTraffic() throws {
        let uploading = try #require(LibtorrentEventMapper.snapshot(
            from: LibtorrentDownloadEvent(
                event: .status,
                name: "Uploading Seed",
                progress: 1,
                downloadRate: 128,
                uploadRate: 512,
                totalDone: 1_000,
                totalWanted: 1_000,
                state: "seeding",
                isSeed: true,
                isPaused: false,
                hasMetadata: true,
                infoHash: "cccccccccccccccccccccccccccccccccccccccc"
            ),
            fallback: nil
        ))
        let stalled = try #require(LibtorrentEventMapper.snapshot(
            from: LibtorrentDownloadEvent(
                event: .status,
                name: "Stalled Seed",
                progress: 1,
                downloadRate: 0,
                uploadRate: 0,
                totalDone: 1_000,
                totalWanted: 1_000,
                state: "seeding",
                isSeed: true,
                isPaused: false,
                hasMetadata: true,
                infoHash: "dddddddddddddddddddddddddddddddddddddddd"
            ),
            fallback: nil
        ))

        #expect(uploading.state == .stoppedUploading)
        #expect(uploading.downloadRateBytesPerSecond == 0)
        #expect(uploading.uploadRateBytesPerSecond == 0)
        #expect(stalled.state == .stoppedUploading)
        #expect(stalled.uploadRateBytesPerSecond == 0)
    }

    @Test func mapperPreservesForcedStartAndPausedAutoManagedState() throws {
        let forced = try #require(LibtorrentEventMapper.snapshot(
            from: LibtorrentDownloadEvent(
                event: .status,
                name: "Forced Download",
                progress: 0.25,
                downloadRate: 256,
                uploadRate: 0,
                totalDone: 250,
                totalWanted: 1_000,
                state: "downloading",
                isSeed: false,
                isPaused: false,
                isAutoManaged: false,
                hasMetadata: true,
                infoHash: "abababababababababababababababababababab",
                queuePosition: -1
            ),
            fallback: nil
        ))
        let paused = try #require(LibtorrentEventMapper.snapshot(
            from: LibtorrentDownloadEvent(
                event: .paused,
                name: "Paused Download",
                progress: 0.25,
                downloadRate: 256,
                uploadRate: 0,
                totalDone: 250,
                totalWanted: 1_000,
                state: "downloading",
                isSeed: false,
                isPaused: true,
                isAutoManaged: false,
                isForcedStart: false,
                hasMetadata: true,
                infoHash: "acacacacacacacacacacacacacacacacacacacac",
                queuePosition: -1
            ),
            fallback: nil
        ))

        #expect(forced.state == .forcedDownloading)
        #expect(forced.queue.position == nil)
        #expect(forced.queue.isForcedStart)
        #expect(paused.state == .stoppedDownloading)
        #expect(paused.queue.position == nil)
        #expect(paused.queue.isForcedStart == false)
    }

    @Test func actorAddsTorrentFileThroughSwiftNativeRequest() async throws {
        let torrentFile = URL(fileURLWithPath: "/tmp/Legal File.torrent")
        let savePath = URL(fileURLWithPath: "/tmp/QBTSwiftTorrentFile", isDirectory: true)
        let downloader = RecordingLibtorrentDownloader(fileEvents: [
            LibtorrentDownloadEvent(
                event: .sessionActive,
                name: "Legal File",
                progress: 0.1,
                downloadRate: 1_024,
                uploadRate: 0,
                totalDone: 100,
                totalWanted: 1_000,
                state: "downloading",
                isSeed: false,
                isPaused: false,
                hasMetadata: true,
                savePath: savePath.path,
                infoHash: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
            )
        ])
        let engine = LibtorrentTorrentEngine(downloader: downloader)

        let snapshot = try await engine.addTorrentFile(
            AddTorrentFileEngineRequest(fileURL: torrentFile, saveDirectory: savePath)
        )
        let storedSnapshots = await engine.snapshots()

        #expect(snapshot.id.rawValue == "btih:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
        #expect(snapshot.name == "Legal File")
        #expect(snapshot.savePath == savePath.path)
        #expect(storedSnapshots == [snapshot])
    }

    @Test func actorPassesStartPausedTorrentFileRequestToDownloader() async throws {
        let torrentFile = URL(fileURLWithPath: "/tmp/Paused File.torrent")
        let savePath = URL(fileURLWithPath: "/tmp/QBTSwiftPausedTorrentFile", isDirectory: true)
        let resumeData = Data("paused-file-resume".utf8)
        let downloader = RecordingStartModeLibtorrentDownloader(fileEvents: [
            LibtorrentDownloadEvent(
                event: .paused,
                name: "Paused File",
                progress: 0,
                downloadRate: 0,
                uploadRate: 0,
                totalDone: 0,
                totalWanted: 1_000,
                state: "downloading",
                isSeed: false,
                isPaused: true,
                hasMetadata: true,
                savePath: savePath.path,
                infoHash: "edededededededededededededededededededed"
            )
        ])
        let engine = LibtorrentTorrentEngine(downloader: downloader)

        let snapshot = try await engine.addTorrentFile(
            AddTorrentFileEngineRequest(
                fileURL: torrentFile,
                saveDirectory: savePath,
                startImmediately: false,
                resumeData: resumeData
            )
        )

        #expect(snapshot.state == .stoppedDownloading)
        #expect(downloader.recordedFileRequest?.startImmediately == false)
        #expect(downloader.recordedFileRequest?.resumeData == resumeData)
    }

    @Test func actorPassesStartPausedMagnetRequestToDownloader() async throws {
        let savePath = URL(fileURLWithPath: "/tmp/QBTSwiftPausedMagnet", isDirectory: true)
        let magnetURI = "magnet:?xt=urn:btih:abababababababababababababababababababab&dn=Paused%20Magnet"
        let resumeData = Data("paused-magnet-resume".utf8)
        let downloader = RecordingStartModeLibtorrentDownloader()
        let engine = LibtorrentTorrentEngine(downloader: downloader)

        let snapshot = try await engine.addMagnet(
            AddMagnetRequest(
                magnetURI: magnetURI,
                saveDirectory: savePath,
                startImmediately: false,
                resumeData: resumeData
            )
        )

        #expect(snapshot.state == .stoppedDownloading)
        #expect(downloader.recordedMagnetRequest?.startImmediately == false)
        #expect(downloader.recordedMagnetRequest?.resumeData == resumeData)
    }

    @Test func actorNormalizesDuplicateTorrentFileBridgeErrors() async {
        let torrentFile = URL(fileURLWithPath: "/tmp/Duplicate File.torrent")
        let savePath = URL(fileURLWithPath: "/tmp/QBTSwiftDuplicateTorrentFile", isDirectory: true)
        let downloader = RecordingStartModeLibtorrentDownloader(fileError: .duplicateTorrent)
        let engine = LibtorrentTorrentEngine(downloader: downloader)

        await #expect(throws: TorrentEngineError.rejected(.duplicate(TorrentID(rawValue: "file:\(torrentFile.standardizedFileURL.path)")))) {
            _ = try await engine.addTorrentFile(
                AddTorrentFileEngineRequest(fileURL: torrentFile, saveDirectory: savePath)
            )
        }
    }

    @Test func actorUnsupportedWorkflowCommandsRemainExplicitlyUnimplementedUntilBridgeSupportExists() async throws {
        let torrentFile = URL(fileURLWithPath: "/tmp/Workflow.torrent")
        let savePath = URL(fileURLWithPath: "/tmp/QBTSwiftWorkflow", isDirectory: true)
        let downloader = RecordingLibtorrentDownloader(fileEvents: [
            LibtorrentDownloadEvent(
                event: .trackerReply,
                numPeers: 8,
                numSeeds: 3,
                trackerURL: "https://tracker.example/announce"
            ),
            LibtorrentDownloadEvent(
                event: .status,
                name: "Workflow Original",
                progress: 0.4,
                downloadRate: 2_048,
                uploadRate: 512,
                totalDone: 400,
                totalWanted: 1_000,
                state: "downloading",
                isSeed: false,
                isPaused: false,
                hasMetadata: true,
                savePath: savePath.path,
                infoHash: "1212121212121212121212121212121212121212"
            )
        ])
        let engine = LibtorrentTorrentEngine(downloader: downloader)
        let added = try await engine.addTorrentFile(
            AddTorrentFileEngineRequest(fileURL: torrentFile, saveDirectory: savePath)
        )

        await expectUnimplemented {
            _ = try await engine.renameTorrent(id: added.id, to: "Workflow Renamed")
        }
        await expectUnimplemented {
            _ = try await engine.setTorrentLocation(
                id: added.id,
                to: URL(fileURLWithPath: "/Volumes/Workflow", isDirectory: true)
            )
        }
        await expectUnimplemented {
            _ = try await engine.forceRecheckTorrent(id: added.id)
        }
        await expectUnimplemented {
            _ = try await engine.forceReannounceTorrent(id: added.id)
        }
        await expectUnimplemented {
            _ = try await engine.setTorrentShareRules(
                id: added.id,
                shareRules: TorrentShareRuleSnapshot(ratioLimit: 3, seedingTimeLimit: 7_200, stopCondition: .remove)
            )
        }

        let storedSnapshot = try await engine.snapshot(for: added.id)
        #expect(storedSnapshot == added)
    }

    @Test func actorWorkflowCommandsBridgeForceQueueAndLimitsWhenSupported() async throws {
        let torrentFile = URL(fileURLWithPath: "/tmp/BridgeWorkflow.torrent")
        let savePath = URL(fileURLWithPath: "/tmp/QBTSwiftBridgeWorkflow", isDirectory: true)
        let infoHash = "3434343434343434343434343434343434343434"
        let downloader = RecordingLibtorrentDownloader(
            fileEvents: [
                LibtorrentDownloadEvent(
                    event: .status,
                    name: "Bridge Workflow",
                    progress: 0.4,
                    downloadRate: 0,
                    uploadRate: 0,
                    totalDone: 400,
                    totalWanted: 1_000,
                    state: "downloading",
                    isSeed: false,
                    isPaused: false,
                    isAutoManaged: true,
                    isForcedStart: false,
                    hasMetadata: true,
                    savePath: savePath.path,
                    infoHash: infoHash,
                    queuePosition: 1
                )
            ],
            forceStartEvents: [
                LibtorrentDownloadEvent(
                    event: .resumed,
                    name: "Bridge Workflow",
                    progress: 0.4,
                    downloadRate: 1_024,
                    uploadRate: 0,
                    totalDone: 400,
                    totalWanted: 1_000,
                    state: "downloading",
                    isSeed: false,
                    isPaused: false,
                    isAutoManaged: false,
                    isForcedStart: true,
                    hasMetadata: true,
                    savePath: savePath.path,
                    infoHash: infoHash,
                    queuePosition: 1
                )
            ],
            moveEvents: [
                LibtorrentDownloadEvent(
                    event: .status,
                    name: "Bridge Workflow",
                    progress: 0.4,
                    downloadRate: 1_024,
                    uploadRate: 0,
                    totalDone: 400,
                    totalWanted: 1_000,
                    state: "downloading",
                    isSeed: false,
                    isPaused: false,
                    isAutoManaged: false,
                    isForcedStart: true,
                    hasMetadata: true,
                    savePath: savePath.path,
                    infoHash: infoHash,
                    queuePosition: 0
                )
            ],
            setLimitEvents: [
                LibtorrentDownloadEvent(
                    event: .status,
                    name: "Bridge Workflow",
                    progress: 0.4,
                    downloadRate: 1_024,
                    uploadRate: 0,
                    totalDone: 400,
                    totalWanted: 1_000,
                    state: "downloading",
                    isSeed: false,
                    isPaused: false,
                    isAutoManaged: false,
                    isForcedStart: true,
                    hasMetadata: true,
                    savePath: savePath.path,
                    infoHash: infoHash,
                    downloadLimit: 4_096,
                    uploadLimit: 2_048,
                    queuePosition: 0
                )
            ]
        )
        let engine = LibtorrentTorrentEngine(downloader: downloader)
        let added = try await engine.addTorrentFile(
            AddTorrentFileEngineRequest(fileURL: torrentFile, saveDirectory: savePath)
        )
        #expect(added.queue.isForcedStart == false)

        let forced = try await engine.forceStartTorrent(id: added.id)
        #expect(forced.state == .forcedDownloading)
        #expect(forced.queue.isForcedStart)

        let queued = try await engine.moveTorrentInQueue(id: added.id, move: .top)
        #expect(queued.queue.position == 1)
        #expect(queued.queue.isForcedStart)

        let limited = try await engine.setTorrentLimits(
            id: added.id,
            limits: TorrentLimitsSnapshot(downloadLimitBytesPerSecond: 4_096, uploadLimitBytesPerSecond: 2_048)
        )
        #expect(limited.limits.downloadLimitBytesPerSecond == 4_096)
        #expect(limited.limits.uploadLimitBytesPerSecond == 2_048)
        #expect(limited.queue.isForcedStart)
    }

    @Test func actorPauseAndRefreshClearPreviousForcedStartState() async throws {
        let torrentFile = URL(fileURLWithPath: "/tmp/BridgePause.torrent")
        let savePath = URL(fileURLWithPath: "/tmp/QBTSwiftBridgePause", isDirectory: true)
        let infoHash = "5656565656565656565656565656565656565656"
        let pausedEvent = LibtorrentDownloadEvent(
            event: .paused,
            name: "Bridge Pause",
            progress: 0.4,
            downloadRate: 1_024,
            uploadRate: 0,
            totalDone: 400,
            totalWanted: 1_000,
            state: "downloading",
            isSeed: false,
            isPaused: true,
            isAutoManaged: false,
            isForcedStart: false,
            hasMetadata: true,
            savePath: savePath.path,
            infoHash: infoHash,
            queuePosition: -1
        )
        let downloader = RecordingLibtorrentDownloader(
            fileEvents: [
                LibtorrentDownloadEvent(
                    event: .status,
                    name: "Bridge Pause",
                    progress: 0.4,
                    downloadRate: 0,
                    uploadRate: 0,
                    totalDone: 400,
                    totalWanted: 1_000,
                    state: "downloading",
                    isSeed: false,
                    isPaused: false,
                    isAutoManaged: true,
                    isForcedStart: false,
                    hasMetadata: true,
                    savePath: savePath.path,
                    infoHash: infoHash,
                    queuePosition: 0
                )
            ],
            statusEvents: [pausedEvent],
            pauseEvents: [pausedEvent],
            forceStartEvents: [
                LibtorrentDownloadEvent(
                    event: .resumed,
                    name: "Bridge Pause",
                    progress: 0.4,
                    downloadRate: 1_024,
                    uploadRate: 0,
                    totalDone: 400,
                    totalWanted: 1_000,
                    state: "downloading",
                    isSeed: false,
                    isPaused: false,
                    isAutoManaged: false,
                    isForcedStart: true,
                    hasMetadata: true,
                    savePath: savePath.path,
                    infoHash: infoHash,
                    queuePosition: -1
                )
            ]
        )
        let engine = LibtorrentTorrentEngine(downloader: downloader)
        let added = try await engine.addTorrentFile(
            AddTorrentFileEngineRequest(fileURL: torrentFile, saveDirectory: savePath)
        )
        _ = try await engine.forceStartTorrent(id: added.id)

        try await engine.stopTorrent(id: added.id)
        let stopped = try await engine.snapshot(for: added.id)

        #expect(stopped.state == .stoppedDownloading)
        #expect(stopped.queue.isForcedStart == false)

        let refreshed = try await engine.refreshSnapshots()
        let refreshedStored = try await engine.snapshot(for: added.id)

        #expect(refreshed.first?.state == .stoppedDownloading)
        #expect(refreshed.first?.queue.isForcedStart == false)
        #expect(refreshedStored.queue.isForcedStart == false)
    }

    @Test func bridgeMissingTorrentErrorMapsToEngineMissingTorrent() async throws {
        let id = TorrentID(rawValue: "btih:9999999999999999999999999999999999999999")
        let snapshot = TorrentSnapshot(
            id: id,
            name: "Missing Handle",
            progress: 0,
            state: .downloading,
            sizeBytes: 1_000,
            downloadRateBytesPerSecond: 0,
            uploadRateBytesPerSecond: 0,
            ratio: 0,
            eta: nil,
            category: "",
            tags: [],
            trackers: []
        )
        let downloader = RecordingLibtorrentDownloader(
            statusEvents: [
                LibtorrentDownloadEvent(
                    event: .status,
                    name: snapshot.name,
                    progress: snapshot.progress,
                    downloadRate: 0,
                    uploadRate: 0,
                    totalDone: 0,
                    totalWanted: snapshot.sizeBytes,
                    state: "downloading",
                    isSeed: false,
                    isPaused: false,
                    hasMetadata: true,
                    infoHash: "9999999999999999999999999999999999999999"
                )
            ],
            startError: .missingTorrent,
            pauseError: .missingTorrent,
            removeError: .missingTorrent
        )
        let engine = LibtorrentTorrentEngine(downloader: downloader)
        _ = try await engine.refreshSnapshots()

        await expectMissingTorrent(id) {
            try await engine.startTorrent(id: id)
        }
        await expectMissingTorrent(id) {
            try await engine.stopTorrent(id: id)
        }
        await expectMissingTorrent(id) {
            try await engine.removeTorrent(id: id, deletingFiles: false)
        }
    }

    @Test func bridgeMissingTorrentErrorNormalizesToMissingTorrent() {
        let error = LibtorrentBridgeError(code: .missingTorrent, message: "Missing torrent")

        #expect(LibtorrentDownloader.bridgeError(error) == .missingTorrent)
    }

    @Test func diffFlagsPeerExchangeAsRuntimeChange() {
        var updated = TorrentSessionSettings.defaults
        updated.bitTorrent.isPeXEnabled = false

        let changes = TorrentSessionSettingsDiff().changes(from: .defaults, to: updated)

        #expect(changes.connectionChanged == false)
        #expect(changes.proxyChanged == false)
        #expect(changes.speedChanged == false)
        #expect(changes.bitTorrentRuntimeChanged)
        #expect(changes.advancedChanged == false)
        #expect(changes.dhtChanged == false)
        #expect(changes.localDiscoveryChanged == false)
        #expect(changes.peerExchangeChanged)
    }

    @Test func actorAppliesSessionSettingsThroughDownloader() async throws {
        let downloader = RecordingSessionSettingsLibtorrentDownloader()
        let engine = LibtorrentTorrentEngine(downloader: downloader)
        var settings = TorrentSessionSettings.defaults
        settings.connection.listenPort = 51_113
        settings.connection.portMappingEnabled = false
        settings.connection.maximumConnectionsPerTorrent = 80
        settings.connection.maximumConnections = 250
        settings.bitTorrent.isPeXEnabled = false

        try await engine.apply(settings)

        #expect(downloader.recordedSettings == settings)
    }

    @Test func downloaderMapsSessionSettingsToBridgePayload() throws {
        let bridge = RecordingSessionSettingsBridge()
        let downloader = LibtorrentDownloader(sessionSettingsBridge: bridge)
        let settings = TorrentSessionSettings(
            connection: TorrentConnectionSettings(
                listenPort: 51_514,
                portMappingEnabled: true,
                maximumConnections: 400,
                maximumConnectionsPerTorrent: 40,
                allowIncomingConnections: true
            ),
            proxy: TorrentProxySettings(
                kind: .socks5,
                host: " proxy.example ",
                port: 10_800,
                useForBitTorrent: true,
                useForRSS: false,
                useForGeneralRequests: false,
                proxyPeerConnections: true
            ),
            speed: TorrentSessionSpeedSettings(
                downloadLimitBytesPerSecond: 1_024 * 1_024,
                uploadLimitBytesPerSecond: 256 * 1_024,
                alternativeDownloadLimitBytesPerSecond: 10 * 1_024,
                alternativeUploadLimitBytesPerSecond: 10 * 1_024,
                isAlternativeLimitEnabled: false,
                scheduler: .defaults,
                limitUTPRate: false,
                includeProtocolOverhead: true,
                limitLocalPeerRates: false
            ),
            bitTorrent: BitTorrentSessionSettings(
                isDHTEnabled: false,
                isPeXEnabled: false,
                isLSDEnabled: false
            ),
            advanced: AdvancedLibtorrentSettings(
                connectionSpeed: 45,
                requestQueueSize: 900,
                dhtBootstrapNodes: "node.example:6881"
            )
        )

        try downloader.applySessionSettings(settings)
        let payload = try #require(bridge.recordedSettings)

        #expect(payload.allowIncomingConnections)
        #expect(payload.listenPort == 51_514)
        #expect(payload.enablePortMapping)
        #expect(payload.maximumConnections == 400)
        #expect(payload.maximumConnectionsPerTorrent == 40)
        #expect(payload.downloadLimitBytesPerSecond == 1_024 * 1_024)
        #expect(payload.uploadLimitBytesPerSecond == 256 * 1_024)
        #expect(payload.enableDHT == false)
        #expect(payload.enableLocalServiceDiscovery == false)
        #expect(payload.enablePeerExchange == false)
        #expect(payload.limitUTPRate == false)
        #expect(payload.includeProtocolOverhead)
        #expect(payload.limitLocalPeerRates == false)
        #expect(payload.proxyKind == "socks5")
        #expect(payload.proxyHost == "proxy.example")
        #expect(payload.proxyPort == 10_800)
        #expect(payload.proxyPeerConnections)
        #expect(payload.proxyHostnames)
        #expect(payload.connectionSpeed == 45)
        #expect(payload.requestQueueSize == 900)
        #expect(payload.dhtBootstrapNodes == "node.example:6881")
    }

    @Test func downloaderUsesSchedulerActiveAlternativeSpeedLimits() throws {
        let bridge = RecordingSessionSettingsBridge()
        let downloader = LibtorrentDownloader(sessionSettingsBridge: bridge)
        var settings = TorrentSessionSettings.defaults
        settings.speed = TorrentSessionSpeedSettings(
            downloadLimitBytesPerSecond: 1_024 * 1_024,
            uploadLimitBytesPerSecond: 256 * 1_024,
            alternativeDownloadLimitBytesPerSecond: 64 * 1_024,
            alternativeUploadLimitBytesPerSecond: 32 * 1_024,
            isAlternativeLimitEnabled: false,
            scheduler: SpeedSchedulerPreferences(
                isEnabled: true,
                startMinuteOfDay: 0,
                endMinuteOfDay: 1_439,
                days: .everyDay
            ),
            limitUTPRate: true,
            includeProtocolOverhead: false,
            limitLocalPeerRates: true
        )

        try downloader.applySessionSettings(settings)
        let payload = try #require(bridge.recordedSettings)

        #expect(payload.downloadLimitBytesPerSecond == 64 * 1_024)
        #expect(payload.uploadLimitBytesPerSecond == 32 * 1_024)
    }

    @Test func actorDoesNotResurrectTorrentWhenStartCompletesAfterRemoval() async throws {
        let infoHash = "abababababababababababababababababababab"
        let torrentFile = URL(fileURLWithPath: "/tmp/Reentrant.torrent")
        let savePath = URL(fileURLWithPath: "/tmp/QBTSwiftReentrant", isDirectory: true)
        let downloader = DelayedStartLibtorrentDownloader(
            fileEvents: [
                LibtorrentDownloadEvent(
                    event: .status,
                    name: "Reentrant",
                    progress: 0.5,
                    downloadRate: 0,
                    uploadRate: 0,
                    totalDone: 500,
                    totalWanted: 1_000,
                    state: "paused",
                    isSeed: false,
                    isPaused: true,
                    hasMetadata: true,
                    savePath: savePath.path,
                    infoHash: infoHash
                )
            ],
            startEvents: [
                LibtorrentDownloadEvent(
                    event: .status,
                    name: "Reentrant",
                    progress: 0.5,
                    downloadRate: 1_024,
                    uploadRate: 0,
                    totalDone: 500,
                    totalWanted: 1_000,
                    state: "downloading",
                    isSeed: false,
                    isPaused: false,
                    hasMetadata: true,
                    savePath: savePath.path,
                    infoHash: infoHash
                )
            ]
        )
        let engine = LibtorrentTorrentEngine(downloader: downloader)
        let added = try await engine.addTorrentFile(
            AddTorrentFileEngineRequest(fileURL: torrentFile, saveDirectory: savePath)
        )

        let startTask = Task {
            do {
                try await engine.startTorrent(id: added.id)
                return Optional<TorrentEngineError>.none
            } catch let error as TorrentEngineError {
                return error
            } catch {
                return nil
            }
        }
        try await downloader.waitForStartCall()

        try await engine.removeTorrent(id: added.id, deletingFiles: false)
        downloader.releaseStart()

        let startError = await startTask.value
        #expect(startError == .rejected(.missingTorrent(added.id)))
        #expect(await engine.snapshots() == [])
    }

    @Test func delayedStartDownloaderStartWaitTimesOutWhenStartNeverArrives() async {
        let downloader = DelayedStartLibtorrentDownloader(fileEvents: [], startEvents: [])

        await #expect(throws: DelayedStartLibtorrentDownloaderError.timedOut) {
            try await downloader.waitForStartCall(timeoutNanoseconds: 1_000_000)
        }
    }

    @Test func mapperBuildsBestEffortDetailsFromBridgeEvents() throws {
        let snapshot = try #require(LibtorrentEventMapper.snapshot(
            from: [
                LibtorrentDownloadEvent(
                    event: .trackerAnnounce,
                    trackerURL: "https://tracker.example/announce"
                ),
                LibtorrentDownloadEvent(
                    event: .trackerReply,
                    numPeers: 12,
                    numSeeds: 4,
                    trackerURL: "https://tracker.example/announce"
                ),
                LibtorrentDownloadEvent(
                    event: .peerConnected,
                    endpoint: "198.51.100.10:6881",
                    direction: "out"
                ),
                LibtorrentDownloadEvent(
                    event: .status,
                    name: "Detailed",
                    progress: 0.5,
                    downloadRate: 1_024,
                    uploadRate: 256,
                    totalDone: 4_000_000,
                    totalWanted: 8_000_000,
                    state: "downloading",
                    isSeed: false,
                    isPaused: false,
                    hasMetadata: true,
                    savePath: "/tmp",
                    infoHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    files: [
                        LibtorrentFileEvent(
                            path: "Detailed/track01.flac",
                            sizeBytes: 6_000_000,
                            completedBytes: 3_000_000,
                            progress: nil,
                            priority: "high"
                        ),
                        LibtorrentFileEvent(
                            path: "Detailed/track02.flac",
                            sizeBytes: 2_000_000,
                            completedBytes: 1_000_000,
                            progress: nil,
                            priority: "normal"
                        )
                    ],
                    pieceCount: 4,
                    availablePieces: 2,
                    distributedCopies: 1.5
                )
            ],
            fallback: nil
        ))

        #expect(snapshot.trackers.first?.status == .working)
        #expect(snapshot.trackers.first?.peers == 12)
        #expect(snapshot.trackers.first?.seeds == 4)
        #expect(snapshot.peers.first?.address == "198.51.100.10:6881")
        #expect(snapshot.files.map(\.path) == ["Detailed/track01.flac", "Detailed/track02.flac"])
        #expect(snapshot.files.first?.progress == 0.5)
        #expect(snapshot.files.first?.priority == .high)
        #expect(snapshot.pieceAvailability?.totalPieces == 4)
        #expect(snapshot.pieceAvailability?.availablePieces == 2)
        #expect(snapshot.pieceAvailability?.distributedCopies == 1.5)
    }

    @Test func actorRefreshMapsStatusesIntoSnapshots() async throws {
        let downloader = RecordingLibtorrentDownloader(statusEvents: [
            LibtorrentDownloadEvent(
                event: .status,
                name: "Active",
                progress: 0.25,
                downloadRate: 4_096,
                uploadRate: 128,
                totalDone: 250,
                totalWanted: 1_000,
                state: "downloading",
                isSeed: false,
                isPaused: false,
                hasMetadata: true,
                savePath: "/tmp",
                infoHash: "ffffffffffffffffffffffffffffffffffffffff"
            )
        ])
        let engine = LibtorrentTorrentEngine(downloader: downloader)

        let snapshots = try await engine.refreshSnapshots()

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.state == .downloading)
        #expect(snapshots.first?.downloadRateBytesPerSecond == 4_096)
        #expect(snapshots.first?.files.first?.path == "Active")
        #expect(snapshots.first?.pieceAvailability != nil)
        #expect(await engine.snapshots() == snapshots)
    }

    @Test func actorRefreshPreservesForcedStartFromBridgeFlags() async throws {
        let downloader = RecordingLibtorrentDownloader(statusEvents: [
            LibtorrentDownloadEvent(
                event: .status,
                name: "Forced Active",
                progress: 0.25,
                downloadRate: 4_096,
                uploadRate: 128,
                totalDone: 250,
                totalWanted: 1_000,
                state: "downloading",
                isSeed: false,
                isPaused: false,
                isAutoManaged: false,
                isForcedStart: true,
                hasMetadata: true,
                savePath: "/tmp",
                infoHash: "fafafafafafafafafafafafafafafafafafafafa",
                queuePosition: -1
            )
        ])
        let engine = LibtorrentTorrentEngine(downloader: downloader)

        let snapshots = try await engine.refreshSnapshots()

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.state == .forcedDownloading)
        #expect(snapshots.first?.queue.position == nil)
        #expect(snapshots.first?.queue.isForcedStart == true)
        #expect(await engine.snapshots() == snapshots)
    }
}

private struct RecordingLibtorrentDownloader: LibtorrentDownloading {
    var magnetEvents: [LibtorrentDownloadEvent] = []
    var fileEvents: [LibtorrentDownloadEvent] = []
    var statusEvents: [LibtorrentDownloadEvent] = []
    var startEvents: [LibtorrentDownloadEvent] = []
    var pauseEvents: [LibtorrentDownloadEvent] = []
    var removeEvents: [LibtorrentDownloadEvent] = []
    var forceStartEvents: [LibtorrentDownloadEvent] = []
    var moveEvents: [LibtorrentDownloadEvent] = []
    var setLimitEvents: [LibtorrentDownloadEvent] = []
    var startError: LibtorrentDownloader.DownloaderError?
    var pauseError: LibtorrentDownloader.DownloaderError?
    var removeError: LibtorrentDownloader.DownloaderError?

    func downloadMagnet(
        _ magnet: String,
        savePath: URL,
        timeout: TimeInterval,
        metadataOnly: Bool,
        startImmediately: Bool,
        resumeData: Data?,
        peer: String?
    ) throws -> [LibtorrentDownloadEvent] {
        magnetEvents
    }

    func downloadTorrentFile(
        _ torrentFile: URL,
        savePath: URL,
        timeout: TimeInterval,
        startImmediately: Bool,
        resumeData: Data?
    ) throws -> [LibtorrentDownloadEvent] {
        fileEvents
    }

    func activeTorrentStatuses() throws -> [LibtorrentDownloadEvent] {
        statusEvents
    }

    func startTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        if let startError {
            throw startError
        }

        return startEvents
    }

    func pauseTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        if let pauseError {
            throw pauseError
        }

        return pauseEvents
    }

    func removeTorrent(infoHash: String, deletingFiles: Bool) throws -> [LibtorrentDownloadEvent] {
        if let removeError {
            throw removeError
        }

        return removeEvents
    }

    func forceStartTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        forceStartEvents
    }

    func moveTorrent(infoHash: String, queueMove: TorrentQueueMove) throws -> [LibtorrentDownloadEvent] {
        moveEvents
    }

    func setTorrentLimits(
        infoHash: String,
        downloadLimitBytesPerSecond: Int64?,
        uploadLimitBytesPerSecond: Int64?
    ) throws -> [LibtorrentDownloadEvent] {
        setLimitEvents
    }

    func applySessionSettings(_ settings: TorrentSessionSettings) throws {}
}

private final class RecordingSessionSettingsLibtorrentDownloader: LibtorrentDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var _recordedSettings: TorrentSessionSettings?

    var recordedSettings: TorrentSessionSettings? {
        lock.lock()
        defer { lock.unlock() }
        return _recordedSettings
    }

    func downloadMagnet(
        _ magnet: String,
        savePath: URL,
        timeout: TimeInterval,
        metadataOnly: Bool,
        startImmediately: Bool,
        resumeData: Data?,
        peer: String?
    ) throws -> [LibtorrentDownloadEvent] {
        return []
    }

    func downloadTorrentFile(
        _ torrentFile: URL,
        savePath: URL,
        timeout: TimeInterval,
        startImmediately: Bool,
        resumeData: Data?
    ) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func activeTorrentStatuses() throws -> [LibtorrentDownloadEvent] {
        []
    }

    func startTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func pauseTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func removeTorrent(infoHash: String, deletingFiles: Bool) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func forceStartTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func moveTorrent(infoHash: String, queueMove: TorrentQueueMove) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func setTorrentLimits(
        infoHash: String,
        downloadLimitBytesPerSecond: Int64?,
        uploadLimitBytesPerSecond: Int64?
    ) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func applySessionSettings(_ settings: TorrentSessionSettings) throws {
        lock.lock()
        _recordedSettings = settings
        lock.unlock()
    }
}

private final class RecordingSessionSettingsBridge: LibtorrentSessionSettingsBridging, @unchecked Sendable {
    private let lock = NSLock()
    private var _recordedSettings: LibtorrentBridgeSessionSettings?

    var recordedSettings: LibtorrentBridgeSessionSettings? {
        lock.lock()
        defer { lock.unlock() }
        return _recordedSettings
    }

    func apply(_ settings: LibtorrentBridgeSessionSettings) throws {
        lock.lock()
        _recordedSettings = settings
        lock.unlock()
    }
}

private final class RecordingStartModeLibtorrentDownloader: LibtorrentDownloading, @unchecked Sendable {
    struct MagnetRequest: Equatable, Sendable {
        var magnet: String
        var savePath: URL
        var timeout: TimeInterval
        var metadataOnly: Bool
        var startImmediately: Bool
        var resumeData: Data?
        var peer: String?
    }

    struct FileRequest: Equatable, Sendable {
        var torrentFile: URL
        var savePath: URL
        var timeout: TimeInterval
        var startImmediately: Bool
        var resumeData: Data?
    }

    private let fileEvents: [LibtorrentDownloadEvent]
    private let fileError: LibtorrentDownloader.DownloaderError?
    private let lock = NSLock()
    private var _recordedMagnetRequest: MagnetRequest?
    private var _recordedFileRequest: FileRequest?

    init(
        fileEvents: [LibtorrentDownloadEvent] = [],
        fileError: LibtorrentDownloader.DownloaderError? = nil
    ) {
        self.fileEvents = fileEvents
        self.fileError = fileError
    }

    var recordedFileRequest: FileRequest? {
        lock.lock()
        defer { lock.unlock() }
        return _recordedFileRequest
    }

    var recordedMagnetRequest: MagnetRequest? {
        lock.lock()
        defer { lock.unlock() }
        return _recordedMagnetRequest
    }

    func downloadMagnet(
        _ magnet: String,
        savePath: URL,
        timeout: TimeInterval,
        metadataOnly: Bool,
        startImmediately: Bool,
        resumeData: Data?,
        peer: String?
    ) throws -> [LibtorrentDownloadEvent] {
        lock.lock()
        _recordedMagnetRequest = MagnetRequest(
            magnet: magnet,
            savePath: savePath,
            timeout: timeout,
            metadataOnly: metadataOnly,
            startImmediately: startImmediately,
            resumeData: resumeData,
            peer: peer
        )
        lock.unlock()

        return []
    }

    func downloadTorrentFile(
        _ torrentFile: URL,
        savePath: URL,
        timeout: TimeInterval,
        startImmediately: Bool,
        resumeData: Data?
    ) throws -> [LibtorrentDownloadEvent] {
        lock.lock()
        _recordedFileRequest = FileRequest(
            torrentFile: torrentFile,
            savePath: savePath,
            timeout: timeout,
            startImmediately: startImmediately,
            resumeData: resumeData
        )
        lock.unlock()

        if let fileError {
            throw fileError
        }

        return fileEvents
    }

    func activeTorrentStatuses() throws -> [LibtorrentDownloadEvent] {
        []
    }

    func startTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func pauseTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func removeTorrent(infoHash: String, deletingFiles: Bool) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func forceStartTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func moveTorrent(infoHash: String, queueMove: TorrentQueueMove) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func setTorrentLimits(
        infoHash: String,
        downloadLimitBytesPerSecond: Int64?,
        uploadLimitBytesPerSecond: Int64?
    ) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func applySessionSettings(_ settings: TorrentSessionSettings) throws {}
}

private final class DelayedStartLibtorrentDownloader: LibtorrentDownloading, @unchecked Sendable {
    private let fileEvents: [LibtorrentDownloadEvent]
    private let startEvents: [LibtorrentDownloadEvent]
    private let startStateQueue = DispatchQueue(label: "QBTSwiftTests.DelayedStartLibtorrentDownloader.startState")
    private var didEnterStart = false
    private let startRelease = DispatchSemaphore(value: 0)

    init(fileEvents: [LibtorrentDownloadEvent], startEvents: [LibtorrentDownloadEvent]) {
        self.fileEvents = fileEvents
        self.startEvents = startEvents
    }

    func downloadMagnet(
        _ magnet: String,
        savePath: URL,
        timeout: TimeInterval,
        metadataOnly: Bool,
        startImmediately: Bool,
        resumeData: Data?,
        peer: String?
    ) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func downloadTorrentFile(
        _ torrentFile: URL,
        savePath: URL,
        timeout: TimeInterval,
        startImmediately: Bool,
        resumeData: Data?
    ) throws -> [LibtorrentDownloadEvent] {
        fileEvents
    }

    func activeTorrentStatuses() throws -> [LibtorrentDownloadEvent] {
        []
    }

    func startTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        startStateQueue.sync {
            didEnterStart = true
        }
        startRelease.wait()
        return startEvents
    }

    func pauseTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func removeTorrent(infoHash: String, deletingFiles: Bool) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func forceStartTorrent(infoHash: String) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func moveTorrent(infoHash: String, queueMove: TorrentQueueMove) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func setTorrentLimits(
        infoHash: String,
        downloadLimitBytesPerSecond: Int64?,
        uploadLimitBytesPerSecond: Int64?
    ) throws -> [LibtorrentDownloadEvent] {
        []
    }

    func applySessionSettings(_ settings: TorrentSessionSettings) throws {}

    func waitForStartCall(timeoutNanoseconds: UInt64 = 2_000_000_000) async throws {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutNanoseconds) / 1_000_000_000)
        while true {
            let didEnterStart = startStateQueue.sync {
                self.didEnterStart
            }
            if didEnterStart {
                return
            }
            if Date() >= deadline {
                throw DelayedStartLibtorrentDownloaderError.timedOut
            }
            try await Task.sleep(nanoseconds: min(10_000_000, timeoutNanoseconds))
        }
    }

    func releaseStart() {
        startRelease.signal()
    }
}

private enum DelayedStartLibtorrentDownloaderError: Error, Equatable {
    case timedOut
}

private func expectUnimplemented(_ operation: () async throws -> Void) async {
    var caughtError: TorrentEngineError?
    do {
        try await operation()
    } catch let error as TorrentEngineError {
        caughtError = error
    } catch {
        caughtError = nil
    }

    #expect(caughtError == .unimplemented)
}

private func expectMissingTorrent(_ id: TorrentID, _ operation: () async throws -> Void) async {
    var caughtError: TorrentEngineError?
    do {
        try await operation()
    } catch let error as TorrentEngineError {
        caughtError = error
    } catch {
        caughtError = nil
    }

    #expect(caughtError == .rejected(.missingTorrent(id)))
}
