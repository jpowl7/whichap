import Foundation

// MARK: - BSSIDMapping

/// Loads and queries a BSSID-to-AP-name mapping table.
/// Supports Ruckus Data Studio JSON and simple CSV formats.
final class BSSIDMapping {

    // MARK: Singleton

    static let shared = BSSIDMapping()

    enum Source { case bundled, file, manual }

    // MARK: Properties

    /// Mapping from normalized BSSID (uppercase, zero-padded, colon-separated)
    /// to AP name string.
    private var mapping: [String: String] = [:]

    /// Tracks the source of each BSSID entry.
    private var sources: [String: Source] = [:]

    /// Whether any mappings are loaded.
    var isEmpty: Bool {
        return mapping.isEmpty
    }

    private static let manualEntriesKey = "manualMappingEntries"

    // MARK: Lifecycle

    private init() {
        loadBundledMapping()
        loadManualEntries()
    }

    // MARK: Loading — bundled JSON

    /// Loads the default mapping from `default-mapping.json` in the app bundle.
    func loadBundledMapping() {
        guard let url = Bundle.main.url(forResource: "default-mapping", withExtension: "json") else {
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            return
        }
        loadFromData(data, source: .bundled)
    }

    // MARK: Loading — JSON data

    /// Parses JSON data. Tries Ruckus Data Studio format first, then falls back
    /// to a simple array-of-objects format.
    func loadFromData(_ data: Data, source: Source = .file) {
        // Reject unreasonably large mapping files (10 MB)
        guard data.count < 10_000_000 else { return }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return
        }

        // Clear previous file-imported entries when loading a new file
        if source == .file {
            clearFileEntries()
        }

        // Try Ruckus Data Studio format:
        // {"result":[{"data":[{"apName":"...","bssid":"..."},...],...},...]
        if let root = json as? [String: Any],
           let resultArray = root["result"] as? [[String: Any]],
           let firstResult = resultArray.first,
           let dataArray = firstResult["data"] as? [[String: Any]] {
            parseEntries(dataArray, source: source)
            return
        }

        // Fallback: simple array of {"apName":"...","bssid":"..."} objects.
        if let array = json as? [[String: Any]] {
            parseEntries(array, source: source)
            return
        }
    }

    // MARK: Loading — CSV

    /// Parses CSV text. First line is treated as a header and skipped.
    /// Remaining lines are expected as `apName,bssid`.
    func loadFromCSV(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 1 else { return }

        // Clear previous file-imported entries when loading a new file
        clearFileEntries()

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Split on the first comma only, so AP names containing commas
            // would need quoting — but the spec uses simple CSV.
            guard let commaIndex = trimmed.firstIndex(of: ",") else { continue }

            let apName = String(trimmed[trimmed.startIndex..<commaIndex])
                .trimmingCharacters(in: .whitespaces)
            let bssid = String(trimmed[trimmed.index(after: commaIndex)...])
                .trimmingCharacters(in: .whitespaces)

            guard !apName.isEmpty, !bssid.isEmpty else { continue }

            let normalized = normalizeBSSID(bssid)
            mapping[normalized] = apName
            sources[normalized] = .file
        }
    }

    // MARK: Lookup

    /// Returns the AP name for the given BSSID, or `nil` if not found.
    /// The BSSID is normalized before lookup, so any format is accepted.
    func apName(forBSSID bssid: String) -> String? {
        // Fast path: try direct lookup first (works if already normalized)
        if let name = mapping[bssid] { return name }
        // Slow path: normalize and retry
        let normalized = normalizeBSSID(bssid)
        return mapping[normalized]
    }

    // MARK: Private helpers

    /// Removes all file-sourced entries from the mapping.
    private func clearFileEntries() {
        for (bssid, source) in sources where source == .file {
            mapping.removeValue(forKey: bssid)
        }
        sources = sources.filter { $0.value != .file }
    }

    /// Parses an array of dictionaries containing `apName` and `bssid` keys.
    private func parseEntries(_ entries: [[String: Any]], source: Source) {
        for entry in entries {
            guard let apName = entry["apName"] as? String,
                  let bssid = entry["bssid"] as? String else {
                continue
            }
            let normalized = normalizeBSSID(bssid)
            mapping[normalized] = apName
            sources[normalized] = source
        }
    }

    /// Converts a raw BSSID string to uppercase, zero-padded octets.
    /// e.g. "0:33:58:a9:b5:f0" -> "00:33:58:A9:B5:F0"
    private func normalizeBSSID(_ bssid: String) -> String {
        return bssid
            .split(separator: ":")
            .map { octet -> String in
                let hex = String(octet).uppercased()
                return hex.count == 1 ? "0\(hex)" : hex
            }
            .joined(separator: ":")
    }

    // MARK: Manual entries

    /// Adds or updates a single BSSID → AP name mapping and persists to UserDefaults.
    func addManualEntry(apName: String, bssid: String) {
        let normalized = normalizeBSSID(bssid)
        mapping[normalized] = apName
        sources[normalized] = .manual

        var entries = manualEntries()
        // Replace existing entry for this BSSID, or append new
        if let index = entries.firstIndex(where: { $0["bssid"] == normalized }) {
            entries[index] = ["apName": apName, "bssid": normalized]
        } else {
            entries.append(["apName": apName, "bssid": normalized])
        }
        UserDefaults.standard.set(entries, forKey: Self.manualEntriesKey)
    }

    /// Removes a manual or file entry by BSSID.
    func removeEntry(bssid: String) {
        let normalized = normalizeBSSID(bssid)
        let source = sources[normalized]

        mapping.removeValue(forKey: normalized)
        sources.removeValue(forKey: normalized)

        // Also remove from UserDefaults if it was manual
        if source == .manual {
            var entries = manualEntries()
            entries.removeAll { ($0["bssid"] as? String) == normalized }
            UserDefaults.standard.set(entries, forKey: Self.manualEntriesKey)
        }
    }

    /// Removes a manual entry by BSSID and persists to UserDefaults.
    func removeManualEntry(bssid: String) {
        removeEntry(bssid: bssid)
    }

    /// Returns all manually added entries.
    func manualEntries() -> [[String: String]] {
        return UserDefaults.standard.array(forKey: Self.manualEntriesKey) as? [[String: String]] ?? []
    }

    /// Returns all mappings as (apName, bssid, source) tuples, sorted by AP name.
    func allEntries() -> [(apName: String, bssid: String, source: Source)] {
        return mapping.map { (apName: $0.value, bssid: $0.key, source: sources[$0.key] ?? .bundled) }
            .sorted { $0.apName.localizedCaseInsensitiveCompare($1.apName) == .orderedAscending }
    }

    /// Loads manual entries from UserDefaults into the mapping dictionary.
    private func loadManualEntries() {
        for entry in manualEntries() {
            guard let apName = entry["apName"], let bssid = entry["bssid"] else { continue }
            mapping[bssid] = apName  // Already normalized when saved
            sources[bssid] = .manual
        }
    }
}
