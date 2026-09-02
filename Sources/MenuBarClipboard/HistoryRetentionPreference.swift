import Foundation

enum RetentionUnit: String, CaseIterable, Identifiable {
    case hours = "hours"
    case days = "days"
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var seconds: TimeInterval { self == .hours ? 3600 : 86400 }
}

struct RetentionDuration: Equatable {
    var value: Int
    var unit: RetentionUnit

    static let forever = RetentionDuration(value: 0, unit: .days)

    var isForever: Bool { value == 0 }

    var maxAge: TimeInterval? {
        guard value > 0 else { return nil }
        return TimeInterval(value) * unit.seconds
    }

    var displayLabel: String {
        value == 0 ? "Forever" : "\(value) \(value == 1 ? String(unit.rawValue.dropLast()) : unit.rawValue)"
    }

    static func clamp(value: Int, unit: RetentionUnit) -> Int {
        if value == 0 { return 0 }
        let maxVal = unit == .hours ? 720 : 365
        return min(Swift.max(1, value), maxVal)
    }

    func encoded() -> String { "\(value):\(unit.rawValue)" }

    static func decode(_ string: String) -> RetentionDuration? {
        let parts = string.split(separator: ":").map(String.init)
        guard parts.count == 2,
              let v = Int(parts[0]),
              let u = RetentionUnit(rawValue: parts[1]) else { return nil }
        return RetentionDuration(value: v, unit: u)
    }
}

struct HistoryRetentionPreference {
    var text: RetentionDuration
    var images: RetentionDuration
    var files: RetentionDuration

    static let defaultValue = HistoryRetentionPreference(
        text: .forever,
        images: .forever,
        files: .forever
    )

    static func load(from defaults: UserDefaults = .standard) -> Self {
        HistoryRetentionPreference(
            text: RetentionDuration.decode(defaults.string(forKey: "retention.text") ?? "") ?? .forever,
            images: RetentionDuration.decode(defaults.string(forKey: "retention.images") ?? "") ?? .forever,
            files: RetentionDuration.decode(defaults.string(forKey: "retention.files") ?? "") ?? .forever
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(text.encoded(), forKey: "retention.text")
        defaults.set(images.encoded(), forKey: "retention.images")
        defaults.set(files.encoded(), forKey: "retention.files")
    }
}
