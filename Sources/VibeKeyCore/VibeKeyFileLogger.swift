import Foundation

/// Minimal private JSONL event log used for on-device diagnosis.
/// The logger is append-only and creates its file lazily on the first event.
public final class VibeKeyFileLogger: @unchecked Sendable {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("VibeKeyElements", isDirectory: true)
            .appendingPathComponent("events.jsonl")
    }

    private let queue = DispatchQueue(label: "com.patrickfu.vibekey.filelog", qos: .utility)
    private let url: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let timestampFormatter: ISO8601DateFormatter

    public init(
        url: URL = VibeKeyFileLogger.defaultURL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.url = url
        self.fileManager = fileManager
        self.now = now
        self.timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime]
    }

    /// Test-only synchronization point; production logging remains async.
    func waitForPendingWrites() {
        queue.sync {}
    }

    public func log(_ event: String, fields: [String: String] = [:]) {
        queue.async { [self] in
            do {
                try fileManager.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                var record: [String: String] = [
                    "time": timestampFormatter.string(from: now()),
                    "event": event
                ]
                for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
                    record[key] = value
                }

                let existed = fileManager.fileExists(atPath: url.path)
                if !existed {
                    // Create the private container before any content can appear in it.
                    guard fileManager.createFile(
                        atPath: url.path,
                        contents: nil,
                        attributes: [.posixPermissions: 0o600]
                    ) else {
                        return
                    }
                }

                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
                if permissions != 0o600 {
                    try fileManager.setAttributes(
                        [.posixPermissions: 0o600],
                        ofItemAtPath: url.path
                    )
                }

                let data = try JSONSerialization.data(
                    withJSONObject: record,
                    options: [.sortedKeys]
                )
                if existed {
                    try Data("\n".utf8).append(to: url)
                }
                try data.append(to: url)
            } catch {
                // File logging must never turn a HID/UI event into user-visible failure.
            }
        }
    }
}

private extension Data {
    func append(to url: URL) throws {
        if let handle = FileHandle(forWritingAtPath: url.path) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            handle.write(self)
        } else {
            try write(to: url, options: .atomic)
        }
    }
}
