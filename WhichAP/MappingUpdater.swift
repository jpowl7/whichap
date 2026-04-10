import Foundation
import os

// MARK: - MappingUpdater

/// Periodically fetches BSSID mapping data from a remote HTTPS URL and
/// feeds it to `BSSIDMapping.shared`.  Controlled by UserDefaults keys
/// `mappingSource`, `mappingURL`, and `fetchInterval`.
@available(macOS 13.0, *)
final class MappingUpdater {

    // MARK: Singleton

    static let shared = MappingUpdater()

    // MARK: Private properties

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.whichap", category: "MappingUpdater")

    private var fetchTimer: Timer?

    // MARK: UserDefaults keys

    private enum DefaultsKey {
        static let mappingSource    = "mappingSource"
        static let mappingURL       = "mappingURL"
        static let fetchInterval    = "fetchInterval"
        static let cachedMappingData = "cachedMappingData"
    }

    // MARK: Lifecycle

    private init() {
        // Restore cached mapping so the user sees AP names immediately,
        // before the first remote fetch completes.
        loadCachedMappingIfNeeded()

        // React to settings changes from the preferences window.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: Notification.Name("MappingSourceChanged"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: Notification.Name("MappingURLChanged"),
            object: nil
        )
    }

    // MARK: Public API

    /// Reads the current settings from UserDefaults and starts (or restarts)
    /// the periodic fetch timer.  Call this on app launch and whenever
    /// settings change.
    func startPeriodicFetch() {
        stopPeriodicFetch()

        guard shouldFetch() else {
            logger.debug("Periodic fetch not started — mapping source is not URL or URL is empty.")
            return
        }

        let interval = timerInterval()

        // Delay the very first fetch by 5 seconds so we don't slow down
        // app launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            self.fetchNow()
            self.scheduleTimer(interval: interval)
        }
    }

    /// Stops the periodic fetch timer.
    func stopPeriodicFetch() {
        fetchTimer?.invalidate()
        fetchTimer = nil
    }

    /// Immediately fetches from the configured URL.  Safe to call from
    /// any thread; the URLSession callback dispatches to main.
    func fetchNow() {
        guard shouldFetch() else {
            logger.debug("fetchNow skipped — mapping source is not URL or URL is empty.")
            return
        }

        let defaults = UserDefaults.standard
        guard let urlString = defaults.string(forKey: DefaultsKey.mappingURL),
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            logger.error("fetchNow: invalid or disallowed URL in UserDefaults.")
            return
        }

        logger.info("Fetching mapping from \(url.absoluteString, privacy: .public)")

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Fetch failed: response is not HTTPURLResponse.")
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                self.logger.error("Fetch failed: HTTP \(httpResponse.statusCode)")
                return
            }

            guard let data = data, !data.isEmpty else {
                self.logger.error("Fetch failed: response body is empty.")
                return
            }

            DispatchQueue.main.async {
                BSSIDMapping.shared.loadFromData(data)
                UserDefaults.standard.set(data, forKey: DefaultsKey.cachedMappingData)
                self.logger.info("Mapping updated from remote URL (\(data.count) bytes).")
            }
        }.resume()
    }

    // MARK: Notification handling

    @objc private func handleSettingsChanged() {
        startPeriodicFetch()
    }

    // MARK: Private helpers

    /// Returns `true` when the user has chosen the "url" mapping source
    /// and provided a non-empty URL string.
    private func shouldFetch() -> Bool {
        let defaults = UserDefaults.standard
        let source = defaults.string(forKey: DefaultsKey.mappingSource) ?? "bundled"
        guard source == "url" else { return false }

        let urlString = defaults.string(forKey: DefaultsKey.mappingURL) ?? ""
        return !urlString.isEmpty
    }

    /// Converts the `fetchInterval` UserDefaults value to seconds.
    private func timerInterval() -> TimeInterval {
        let value = UserDefaults.standard.string(forKey: DefaultsKey.fetchInterval) ?? "daily"
        switch value {
        case "hourly":  return 3_600
        case "daily":   return 86_400
        case "weekly":  return 604_800
        default:        return 86_400
        }
    }

    /// Schedules a repeating timer on the main run loop.
    private func scheduleTimer(interval: TimeInterval) {
        fetchTimer?.invalidate()
        fetchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchNow()
        }
    }

    /// If the mapping source is "url" and we have previously-cached data,
    /// load it into BSSIDMapping so the user sees AP names before the first
    /// remote fetch completes.
    private func loadCachedMappingIfNeeded() {
        let defaults = UserDefaults.standard
        let source = defaults.string(forKey: DefaultsKey.mappingSource) ?? "bundled"
        guard source == "url" else { return }

        guard let cachedData = defaults.data(forKey: DefaultsKey.cachedMappingData) else {
            logger.debug("No cached mapping data found in UserDefaults.")
            return
        }

        BSSIDMapping.shared.loadFromData(cachedData)
        logger.info("Loaded cached mapping data (\(cachedData.count) bytes).")
    }
}
