import Foundation

public enum TorrentState: String, CaseIterable, Identifiable, Codable, Sendable {
    case unknown
    case forcedDownloading
    case downloading
    case forcedDownloadingMetadata
    case downloadingMetadata
    case stalledDownloading
    case forcedUploading
    case uploading
    case stalledUploading
    case checkingResumeData
    case queuedDownloading
    case queuedUploading
    case checkingUploading
    case checkingDownloading
    case stoppedDownloading
    case stoppedUploading
    case moving
    case missingFiles
    case error

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unknown:
            "Unknown"
        case .forcedDownloading:
            "Forced Downloading"
        case .downloading:
            "Downloading"
        case .forcedDownloadingMetadata:
            "Forced Metadata"
        case .downloadingMetadata:
            "Downloading Metadata"
        case .stalledDownloading:
            "Stalled Downloading"
        case .forcedUploading:
            "Forced Uploading"
        case .uploading:
            "Uploading"
        case .stalledUploading:
            "Stalled Uploading"
        case .checkingResumeData:
            "Checking Resume Data"
        case .queuedDownloading:
            "Queued Downloading"
        case .queuedUploading:
            "Queued Uploading"
        case .checkingUploading:
            "Checking Uploading"
        case .checkingDownloading:
            "Checking Download"
        case .stoppedDownloading:
            "Stopped"
        case .stoppedUploading:
            "Completed"
        case .moving:
            "Moving"
        case .missingFiles:
            "Missing Files"
        case .error:
            "Error"
        }
    }

    public var systemImage: String {
        switch self {
        case .forcedDownloading, .downloading, .forcedDownloadingMetadata, .downloadingMetadata:
            "arrow.down.circle"
        case .forcedUploading, .uploading:
            "arrow.up.circle"
        case .queuedDownloading, .queuedUploading:
            "clock"
        case .stalledDownloading, .stalledUploading:
            "hourglass"
        case .checkingResumeData, .checkingUploading, .checkingDownloading:
            "checkmark.seal"
        case .stoppedDownloading, .stoppedUploading:
            "pause.circle"
        case .moving:
            "folder.badge.gearshape"
        case .missingFiles:
            "folder.badge.questionmark"
        case .error:
            "exclamationmark.triangle"
        case .unknown:
            "questionmark.circle"
        }
    }

    public var isActive: Bool {
        switch self {
        case .forcedDownloading, .downloading, .forcedDownloadingMetadata, .downloadingMetadata,
                .forcedUploading, .uploading, .checkingResumeData, .checkingUploading,
                .checkingDownloading, .moving:
            true
        case .unknown, .stalledDownloading, .stalledUploading, .queuedDownloading, .queuedUploading,
                .stoppedDownloading, .stoppedUploading, .missingFiles, .error:
            false
        }
    }

    public var isDownloading: Bool {
        switch self {
        case .forcedDownloading, .downloading, .forcedDownloadingMetadata, .downloadingMetadata,
                .stalledDownloading, .queuedDownloading, .checkingDownloading, .stoppedDownloading:
            true
        case .unknown, .forcedUploading, .uploading, .stalledUploading, .checkingResumeData,
                .queuedUploading, .checkingUploading, .stoppedUploading, .moving, .missingFiles,
                .error:
            false
        }
    }

    public var isUploading: Bool {
        switch self {
        case .forcedUploading, .uploading, .stalledUploading, .queuedUploading, .checkingUploading:
            true
        case .unknown, .forcedDownloading, .downloading, .forcedDownloadingMetadata,
                .downloadingMetadata, .stalledDownloading, .checkingResumeData, .queuedDownloading,
                .checkingDownloading, .stoppedDownloading, .moving, .missingFiles, .error:
            false
        case .stoppedUploading:
            false
        }
    }

    public var isCompleted: Bool {
        switch self {
        case .forcedUploading, .uploading, .stalledUploading, .queuedUploading, .checkingUploading,
                .stoppedUploading:
            true
        case .unknown, .forcedDownloading, .downloading, .forcedDownloadingMetadata,
                .downloadingMetadata, .stalledDownloading, .checkingResumeData, .queuedDownloading,
                .checkingDownloading, .stoppedDownloading, .moving, .missingFiles, .error:
            false
        }
    }

    public var isErrored: Bool {
        switch self {
        case .missingFiles, .error:
            true
        case .unknown, .forcedDownloading, .downloading, .forcedDownloadingMetadata,
                .downloadingMetadata, .stalledDownloading, .forcedUploading, .uploading,
                .stalledUploading, .checkingResumeData, .queuedDownloading, .queuedUploading,
                .checkingUploading, .checkingDownloading, .stoppedDownloading, .stoppedUploading,
                .moving:
            false
        }
    }

    public var isStopped: Bool {
        switch self {
        case .stoppedDownloading, .stoppedUploading:
            true
        case .unknown, .forcedDownloading, .downloading, .forcedDownloadingMetadata,
                .downloadingMetadata, .stalledDownloading, .forcedUploading, .uploading,
                .stalledUploading, .checkingResumeData, .queuedDownloading, .queuedUploading,
                .checkingUploading, .checkingDownloading, .moving, .missingFiles, .error:
            false
        }
    }

    public var isChecking: Bool {
        switch self {
        case .checkingResumeData, .checkingUploading, .checkingDownloading:
            true
        case .unknown, .forcedDownloading, .downloading, .forcedDownloadingMetadata,
                .downloadingMetadata, .stalledDownloading, .forcedUploading, .uploading,
                .stalledUploading, .queuedDownloading, .queuedUploading, .stoppedDownloading,
                .stoppedUploading, .moving, .missingFiles, .error:
            false
        }
    }

    public var isStalled: Bool {
        switch self {
        case .stalledDownloading, .stalledUploading:
            true
        case .unknown, .forcedDownloading, .downloading, .forcedDownloadingMetadata,
                .downloadingMetadata, .forcedUploading, .uploading, .checkingResumeData,
                .queuedDownloading, .queuedUploading, .checkingUploading, .checkingDownloading,
                .stoppedDownloading, .stoppedUploading, .moving, .missingFiles, .error:
            false
        }
    }
}
