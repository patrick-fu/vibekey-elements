import Foundation

public enum VibeKeyConfigurationFile {
    public static var defaultURL: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("vibekey", isDirectory: true)
        return base.appendingPathComponent("config.json")
    }

    public static func load(from url: URL = defaultURL) throws -> VibeKeyConfiguration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VibeKeyConfiguration.self, from: data)
    }

    public static func save(_ configuration: VibeKeyConfiguration, to url: URL = defaultURL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
