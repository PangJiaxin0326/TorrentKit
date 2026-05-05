import CryptoKit
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
        try writeSingleFileTorrent(
            source: source,
            announceURL: URL(string: "https://tracker.example/announce")!,
            pieceSize: 16,
            outputURL: torrentFile
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

private func writeSingleFileTorrent(
    source: URL,
    announceURL: URL,
    pieceSize: Int,
    outputURL: URL
) throws {
    let sourceData = try Data(contentsOf: source)
    let pieces = torrentPieces(from: sourceData, pieceSize: pieceSize)
    let torrent = TorrentBValue.dict([
        "announce": .string(announceURL.absoluteString),
        "created by": .string("TorrentKitTests"),
        "info": .dict([
            "length": .int(sourceData.count),
            "name": .string(source.lastPathComponent),
            "piece length": .int(pieceSize),
            "pieces": .bytes(pieces)
        ])
    ])

    try torrent.encoded().write(to: outputURL, options: .atomic)
}

private func torrentPieces(from data: Data, pieceSize: Int) -> Data {
    var pieces = Data()
    var offset = data.startIndex

    while offset < data.endIndex {
        let end = min(offset + pieceSize, data.endIndex)
        pieces.append(Data(Insecure.SHA1.hash(data: data[offset..<end])))
        offset = end
    }

    return pieces
}

private enum TorrentBValue {
    case int(Int)
    case string(String)
    case bytes(Data)
    case dict([String: TorrentBValue])

    func encoded() -> Data {
        var data = Data()
        appendEncoded(to: &data)
        return data
    }

    private func appendEncoded(to data: inout Data) {
        switch self {
        case let .int(value):
            data.appendUTF8("i\(value)e")
        case let .string(value):
            let bytes = Data(value.utf8)
            data.appendUTF8("\(bytes.count):")
            data.append(bytes)
        case let .bytes(bytes):
            data.appendUTF8("\(bytes.count):")
            data.append(bytes)
        case let .dict(values):
            data.appendUTF8("d")
            for key in values.keys.sorted() {
                TorrentBValue.string(key).appendEncoded(to: &data)
                values[key]?.appendEncoded(to: &data)
            }
            data.appendUTF8("e")
        }
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(contentsOf: value.utf8)
    }
}
