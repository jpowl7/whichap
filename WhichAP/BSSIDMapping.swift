import Foundation

// MARK: - BSSIDMapping

/// Loads and queries a BSSID-to-AP-name mapping table.
/// Supports Ruckus Data Studio JSON and simple CSV formats.
final class BSSIDMapping {

    // MARK: Singleton

    static let shared = BSSIDMapping()

    // MARK: Properties

    /// Mapping from normalized BSSID (uppercase, zero-padded, colon-separated)
    /// to AP name string.
    private var mapping: [String: String] = [:]

    /// Whether any mappings are loaded.
    var isEmpty: Bool {
        return mapping.isEmpty
    }

    // MARK: Lifecycle

    private init() {
        loadBundledMapping()
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
        loadFromData(data)
    }

    // MARK: Loading — JSON data

    /// Parses JSON data. Tries Ruckus Data Studio format first, then falls back
    /// to a simple array-of-objects format.
    func loadFromData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return
        }

        // Try Ruckus Data Studio format:
        // {"result":[{"data":[{"apName":"...","bssid":"..."},...],...},...]
        if let root = json as? [String: Any],
           let resultArray = root["result"] as? [[String: Any]],
           let firstResult = resultArray.first,
           let dataArray = firstResult["data"] as? [[String: Any]] {
            parseEntries(dataArray)
            return
        }

        // Fallback: simple array of {"apName":"...","bssid":"..."} objects.
        if let array = json as? [[String: Any]] {
            parseEntries(array)
            return
        }
    }

    // MARK: Loading — CSV

    /// Parses CSV text. First line is treated as a header and skipped.
    /// Remaining lines are expected as `apName,bssid`.
    func loadFromCSV(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 1 else { return }

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
        }
    }

    // MARK: Lookup

    /// Returns the AP name for the given BSSID, or `nil` if not found.
    /// The BSSID is normalized before lookup, so any format is accepted.
    func apName(forBSSID bssid: String) -> String? {
        let normalized = normalizeBSSID(bssid)
        return mapping[normalized]
    }

    // MARK: Private helpers

    /// Parses an array of dictionaries containing `apName` and `bssid` keys.
    private func parseEntries(_ entries: [[String: Any]]) {
        for entry in entries {
            guard let apName = entry["apName"] as? String,
                  let bssid = entry["bssid"] as? String else {
                continue
            }
            let normalized = normalizeBSSID(bssid)
            mapping[normalized] = apName
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
}
