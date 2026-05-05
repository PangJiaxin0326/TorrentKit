import CryptoKit
import Foundation

public struct TorrentCreatorRequest: Equatable, Sendable {
    public var sourceFiles: [URL]
    public var announceURLs: [URL]
    public var webSeedURLs: [URL]
    public var pieceSize: Int
    public var isPrivate: Bool
    public var outputURL: URL?

    public init(
        sourceFiles: [URL],
        announceURLs: [URL],
        webSeedURLs: [URL],
        pieceSize: Int,
        isPrivate: Bool,
        outputURL: URL?
    ) {
        self.sourceFiles = sourceFiles
        self.announceURLs = announceURLs
        self.webSeedURLs = webSeedURLs
        self.pieceSize = pieceSize
        self.isPrivate = isPrivate
        self.outputURL = outputURL
    }
}

public struct CreatedTorrent: Equatable, Sendable {
    public var name: String
    public var totalSizeBytes: Int64
    public var pieceCount: Int
    public var bencodedData: Data
    public var outputURL: URL?

    public init(
        name: String,
        totalSizeBytes: Int64,
        pieceCount: Int,
        bencodedData: Data,
        outputURL: URL?
    ) {
        self.name = name
        self.totalSizeBytes = totalSizeBytes
        self.pieceCount = pieceCount
        self.bencodedData = bencodedData
        self.outputURL = outputURL
    }
}

public enum TorrentCreatorError: Error, Equatable, Sendable {
    case missingSource
    case invalidPieceSize
}

public struct TorrentCreatorService: Sendable {
    public init() {}

    public func create(_ request: TorrentCreatorRequest) throws -> CreatedTorrent {
        guard request.sourceFiles.isEmpty == false else {
            throw TorrentCreatorError.missingSource
        }
        guard request.pieceSize > 0 else {
            throw TorrentCreatorError.invalidPieceSize
        }

        let sortedFiles = request.sourceFiles.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        let fileData = try sortedFiles.map { url in
            (url, try Data(contentsOf: url))
        }
        let pieces = Self.pieces(from: fileData.map(\.1), pieceSize: request.pieceSize)
        let totalSize = fileData.reduce(Int64(0)) { $0 + Int64($1.1.count) }
        let name = sortedFiles.count == 1
            ? sortedFiles[0].lastPathComponent
            : sortedFiles[0].deletingLastPathComponent().lastPathComponent

        var info: [String: BValue] = [
            "name": .string(name),
            "piece length": .int(request.pieceSize),
            "pieces": .bytes(pieces)
        ]

        if request.isPrivate {
            info["private"] = .int(1)
        }

        if sortedFiles.count == 1 {
            info["length"] = .int(Int(totalSize))
        } else {
            info["files"] = .list(fileData.map { url, data in
                .dict([
                    "length": .int(data.count),
                    "path": .list([.string(url.lastPathComponent)])
                ])
            })
        }

        var root: [String: BValue] = [
            "announce": .string(request.announceURLs.first?.absoluteString ?? ""),
            "created by": .string("TorrentKit"),
            "info": .dict(info)
        ]

        if request.announceURLs.count > 1 {
            root["announce-list"] = .list(request.announceURLs.map { .list([.string($0.absoluteString)]) })
        }

        if request.webSeedURLs.isEmpty == false {
            root["url-list"] = .list(request.webSeedURLs.map { .string($0.absoluteString) })
        }

        let data = BValue.dict(root).encoded()
        if let outputURL = request.outputURL {
            try data.write(to: outputURL, options: .atomic)
        }

        return CreatedTorrent(
            name: name,
            totalSizeBytes: totalSize,
            pieceCount: pieces.count / Insecure.SHA1.byteCount,
            bencodedData: data,
            outputURL: request.outputURL
        )
    }

    private static func pieces(from fileData: [Data], pieceSize: Int) -> Data {
        var pieces = Data()
        var buffer = Data()

        for data in fileData {
            buffer.append(data)
            while buffer.count >= pieceSize {
                let piece = buffer.prefix(pieceSize)
                pieces.append(Data(Insecure.SHA1.hash(data: piece)))
                buffer.removeFirst(pieceSize)
            }
        }

        if buffer.isEmpty == false {
            pieces.append(Data(Insecure.SHA1.hash(data: buffer)))
        }

        return pieces
    }
}

private enum BValue {
    case int(Int)
    case string(String)
    case bytes(Data)
    case list([BValue])
    case dict([String: BValue])

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
        case let .list(values):
            data.appendUTF8("l")
            for value in values {
                value.appendEncoded(to: &data)
            }
            data.appendUTF8("e")
        case let .dict(values):
            data.appendUTF8("d")
            for key in values.keys.sorted() {
                BValue.string(key).appendEncoded(to: &data)
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
