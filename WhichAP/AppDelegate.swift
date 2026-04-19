import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "mappingSource": "bundled",
            "mappingURL": "",
            "fetchInterval": "daily",
            "apNameMaxLength": 20,
            "showBand": true,
            "truncateAtColon": true,
            "launchAtLogin": true,
        ])

        // Load file-based mapping if configured
        let source = UserDefaults.standard.string(forKey: "mappingSource") ?? "bundled"
        if source == "file" {
            if let url = resolveBookmarkedMappingFile() {
                let ext = url.pathExtension.lowercased()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }

                if let data = try? Data(contentsOf: url) {
                    if ext == "csv", let text = String(data: data, encoding: .utf8) {
                        BSSIDMapping.shared.loadFromCSV(text)
                    } else {
                        BSSIDMapping.shared.loadFromData(data)
                    }
                }
            }
        }

        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if status != .enabled {
                do {
                    try SMAppService.mainApp.register()
                } catch {
                    NSLog("WhichAP: SMAppService.register() failed: \(error) (status was: \(status.rawValue))")
                }
            }
        }

        statusBarController = StatusBarController()
        MappingUpdater.shared.startPeriodicFetch()
    }

    private func resolveBookmarkedMappingFile() -> URL? {
        // Try security-scoped bookmark first (persists across reboots)
        if let bookmarkData = UserDefaults.standard.data(forKey: "mappingFileBookmark") {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale {
                    // Re-create bookmark from the resolved URL
                    if let newData = try? url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        UserDefaults.standard.set(newData, forKey: "mappingFileBookmark")
                    }
                }
                return url
            }
        }

        // Fall back to plain path (works within same session, pre-bookmark installs)
        if let path = UserDefaults.standard.string(forKey: "mappingFilePath"),
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        return nil
    }
}
