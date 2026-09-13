import Foundation

/// The save is deliberately small and independent of the current night's simulation.
/// A damaged or older settings object must never prevent the application from opening.
final class SaveStore {
    let directory: URL
    private let fileURL: URL
    private let backupURL: URL
    private(set) var lastError: String?
    private let fileManager = FileManager.default

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Morrow Listening Institute", isDirectory: true)
        fileURL = self.directory.appendingPathComponent("progress.json")
        backupURL = self.directory.appendingPathComponent("progress.previous.json")
    }

    func load() -> SaveData {
        lastError = nil
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return (try? decode(Data(contentsOf: backupURL))) ?? SaveData()
        }
        do {
            return try decode(Data(contentsOf: fileURL))
        } catch {
            lastError = "The previous save could not be read. Recovering available progress."
            // Keep the original for recovery instead of repeatedly crashing or overwriting it.
            let stamp = Int(Date().timeIntervalSince1970)
            let quarantine = directory.appendingPathComponent("progress.corrupt-\(stamp)-\(UUID().uuidString.prefix(6)).json")
            try? fileManager.moveItem(at: fileURL, to: quarantine)
            return (try? decode(Data(contentsOf: backupURL))) ?? SaveData()
        }
    }

    func save(_ data: SaveData) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(sanitized(data))
            if let previous = try? Data(contentsOf: fileURL), (try? decode(previous)) != nil {
                try? previous.write(to: backupURL, options: .atomic)
            }
            try encoded.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Progress could not be saved: \(error.localizedDescription)"
        }
    }

    private func decode(_ data: Data) throws -> SaveData {
        // Overlay saved keys on current defaults, so fields added in later releases are safe.
        let defaultsData = try JSONEncoder().encode(SaveData())
        var merged = try JSONSerialization.jsonObject(with: defaultsData) as! [String: Any]
        guard let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for (key, value) in saved where key != "settings" { merged[key] = value }
        if let incomingSettings = saved["settings"] as? [String: Any],
           var settings = merged["settings"] as? [String: Any] {
            for (key, value) in incomingSettings { settings[key] = value }
            merged["settings"] = settings
        }
        let compatibleData = try JSONSerialization.data(withJSONObject: merged)
        return sanitized(try JSONDecoder().decode(SaveData.self, from: compatibleData))
    }

    private func sanitized(_ input: SaveData) -> SaveData {
        var data = input
        func clamp(_ value: Double, _ low: Double, _ high: Double, fallback: Double) -> Double {
            value.isFinite ? min(high, max(low, value)) : fallback
        }
        data.version = 1
        data.completedNights = max(0, min(999_999, data.completedNights))
        data.bestPower = clamp(data.bestPower, 0, 100, fallback: 0)
        data.settings.masterVolume = clamp(data.settings.masterVolume, 0, 1, fallback: 0.75)
        data.settings.ambienceVolume = clamp(data.settings.ambienceVolume, 0, 1, fallback: 0.65)
        data.settings.effectsVolume = clamp(data.settings.effectsVolume, 0, 1, fallback: 0.85)
        data.settings.sensitivity = clamp(data.settings.sensitivity, 0, 1, fallback: 0.65)
        data.settings.brightness = clamp(data.settings.brightness, 0.6, 1.6, fallback: 1)
        data.settings.graphicsQuality = min(2, max(0, data.settings.graphicsQuality))
        data.discovered = Set(data.discovered.filter { !$0.isEmpty && $0.count < 128 })
        return data
    }
}
