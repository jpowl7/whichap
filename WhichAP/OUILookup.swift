import Foundation

/// Looks up the manufacturer of a network device from its BSSID (MAC address)
/// using the IEEE OUI registry via maclookup.app API.
/// Results are cached in memory to avoid repeated lookups.
final class OUILookup {

    static let shared = OUILookup()

    private var cache: [String: String] = [:]  // OUI prefix -> manufacturer
    private let queue = DispatchQueue(label: "com.whichap.oui-lookup")

    private init() {}

    /// Returns the cached manufacturer name, or nil if not yet looked up.
    /// Triggers an async fetch if the OUI hasn't been seen before.
    func manufacturer(forBSSID bssid: String, completion: ((String?) -> Void)? = nil) {
        guard let oui = Self.extractOUI(bssid) else {
            completion?(nil)
            return
        }

        // Check cache first
        var cached: String?
        queue.sync { cached = cache[oui] }

        if let cached {
            completion?(cached.isEmpty ? nil : cached)
            return
        }

        // Fetch from API
        let urlString = "https://api.maclookup.app/v2/macs/\(oui)"
        guard let url = URL(string: urlString) else {
            completion?(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let found = json["found"] as? Bool, found,
                  let company = json["company"] as? String else {
                // Cache empty string to avoid re-fetching failures
                self?.queue.sync { self?.cache[oui] = "" }
                completion?(nil)
                return
            }

            let cleaned = Self.cleanName(company)
            self?.queue.sync { self?.cache[oui] = cleaned }
            completion?(cleaned)
        }.resume()
    }

    private static func extractOUI(_ bssid: String) -> String? {
        let cleaned = bssid
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        guard cleaned.count >= 6 else { return nil }
        return String(cleaned.prefix(6))
    }

    private static func cleanName(_ name: String) -> String {
        var result = name.trimmingCharacters(in: .whitespaces)
        let suffixes = [", Inc.", ", Inc", " Inc.", " Inc",
                        ", LLC", " LLC", ", Ltd.", ", Ltd",
                        " Ltd.", " Ltd", " Corporation", " Corp.",
                        " GmbH", " AG", " S.A.", " Co., Ltd.",
                        " Co.,Ltd.", " Co.", " Incorporated",
                        " Company", " L.P.", " B.V.", " N.V.",
                        " Pty", " PLC", " S.p.A."]
        for suffix in suffixes {
            if result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
                break
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
