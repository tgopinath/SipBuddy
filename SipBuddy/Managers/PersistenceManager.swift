import Foundation

/// Stores the full water log as JSON in Application Support. Local only — nothing
/// leaves the Mac.
final class PersistenceManager {
    let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SipBuddy", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("entries.json")
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func loadEntries() -> [WaterEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([WaterEntry].self, from: data).sorted { $0.date < $1.date }
        } catch {
            // Keep the unreadable file aside instead of overwriting the user's history.
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("entries-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            NSLog("SipBuddy: could not read history (\(error.localizedDescription)); moved to \(backup.lastPathComponent)")
            return []
        }
    }

    func save(_ entries: [WaterEntry]) throws {
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: [.atomic])
    }

    static func csv(for entries: [WaterEntry], unit: VolumeUnit) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm:ss"

        var lines = ["date,time,amount_ml" + (unit == .milliliters ? "" : ",amount_\(unit.symbol)")]
        for e in entries.sorted(by: { $0.date < $1.date }) {
            var line = "\(dateFormatter.string(from: e.date)),\(timeFormatter.string(from: e.date)),\(e.amountML)"
            if unit != .milliliters {
                line += "," + String(format: "%.2f", unit.value(fromML: e.amountML))
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
