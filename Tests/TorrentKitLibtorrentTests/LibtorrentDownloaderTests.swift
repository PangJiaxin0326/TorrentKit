import Foundation
import Testing
@testable import TorrentKit
@testable import TorrentKitLibtorrent

struct LibtorrentDownloaderTests {
    @Test func appliedPerTorrentConnectionLimitAppliesToFutureTorrentFileAdds() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "qbtswift-libtorrent-limit-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sourceDirectory = root.appending(path: "source", directoryHint: .isDirectory)
        let downloadDirectory = root.appending(path: "download", directoryHint: .isDirectory)
        let source = sourceDirectory.appending(path: "limited.bin", directoryHint: .notDirectory)
        let torrentFile = root.appending(path: "limited.torrent", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try Data("future torrent connection cap".utf8).write(to: source)
        _ = try TorrentCreatorService().create(
            TorrentCreatorRequest(
                sourceFiles: [source],
                announceURLs: [URL(string: "https://tracker.example/announce")!],
                webSeedURLs: [],
                pieceSize: 16,
                isPrivate: false,
                outputURL: torrentFile
            )
        )

        let downloader = LibtorrentDownloader()
        var settings = TorrentSessionSettings.defaults
        settings.connection.maximumConnectionsPerTorrent = 7

        defer {
            try? downloader.applySessionSettings(.defaults)
            try? FileManager.default.removeItem(at: root)
        }

        try downloader.applySessionSettings(settings)
        let events = try downloader.downloadTorrentFile(
            torrentFile,
            savePath: downloadDirectory,
            timeout: 1,
            startImmediately: false
        )
        if let infoHash = events.compactMap(\.infoHash).first {
            _ = try? downloader.removeTorrent(infoHash: infoHash, deletingFiles: false)
        }

        let status = try #require(events.first { $0.maximumConnections != nil })
        #expect(status.maximumConnections == 7)
    }

    @Test func selfTestDownloadsLegalLoopbackMagnet() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "qbtswift-libtorrent-native-test-\(UUID().uuidString)")
        let downloader = LibtorrentDownloader()

        let events = try downloader.runSelfTest(root: root, timeout: 60)

        #expect(events.contains { $0.event == .selfTestStarted })
        #expect(events.contains { $0.event == .listenSucceeded })
        #expect(events.contains { $0.event == .metadataReceived })
        #expect(events.contains { $0.event == .peerConnected })
        #expect(events.contains { $0.event == .selfTestFinished })

        let finished = try #require(events.first { $0.event == .selfTestFinished })
        let downloadedPath = try #require(finished.file)
        #expect(FileManager.default.fileExists(atPath: downloadedPath))

        try? FileManager.default.removeItem(at: root)
    }
}
