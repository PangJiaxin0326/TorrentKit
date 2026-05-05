import Foundation

public enum TorrentQueueMove: String, CaseIterable, Identifiable, Sendable {
    case top
    case up
    case down
    case bottom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .top:
            "Move to Top"
        case .up:
            "Move Up"
        case .down:
            "Move Down"
        case .bottom:
            "Move to Bottom"
        }
    }
}
