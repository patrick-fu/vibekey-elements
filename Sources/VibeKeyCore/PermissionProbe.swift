import Foundation

public enum VibeKeyPermissionProbe {
    public static let argument = "--vibekey-permission-probe"

    public static func resultPath(from arguments: [String]) -> String? {
        guard arguments.count == 2,
              arguments[0] == argument,
              !arguments[1].isEmpty else {
            return nil
        }
        return arguments[1]
    }

    public static func encoded(_ reports: [VibeKeyPermissionReport]) -> Data? {
        let statuses = Dictionary(uniqueKeysWithValues: reports.map {
            ($0.permission.rawValue, $0.status.rawValue)
        })
        return try? JSONSerialization.data(withJSONObject: statuses, options: [.sortedKeys])
    }

    public static func decoded(_ data: Data) -> [VibeKeyPermission: VibeKeyPermissionStatus]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }

        var result: [VibeKeyPermission: VibeKeyPermissionStatus] = [:]
        for (key, value) in raw {
            guard let permission = VibeKeyPermission(rawValue: key),
                  let status = VibeKeyPermissionStatus(rawValue: value) else {
                return nil
            }
            result[permission] = status
        }
        return result.count == VibeKeyPermission.allCases.count ? result : nil
    }

    public static func write(_ reports: [VibeKeyPermissionReport], to path: String) -> Bool {
        guard let data = encoded(reports) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
    }

    public static func newlyGranted(
        current: [VibeKeyPermission: VibeKeyPermissionStatus],
        fresh: [VibeKeyPermission: VibeKeyPermissionStatus]
    ) -> [VibeKeyPermission] {
        VibeKeyPermission.allCases.filter {
            current[$0] != .granted && fresh[$0] == .granted
        }
    }
}
