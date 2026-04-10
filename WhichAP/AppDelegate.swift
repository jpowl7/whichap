import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "mappingSource": "bundled",
            "mappingURL": "",
            "fetchInterval": "daily",
            "apNameMaxLength": 20,
            "showBand": true,
            "launchAtLogin": true,
        ])

        // Load file-based mapping if configured
        let source = UserDefaults.standard.string(forKey: "mappingSource") ?? "bundled"
        if source == "file",
           let path = UserDefaults.standard.string(forKey: "mappingFilePath"),
           !path.isEmpty,
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            let ext = (path as NSString).pathExtension.lowercased()
            if ext == "csv", let text = String(data: data, encoding: .utf8) {
                BSSIDMapping.shared.loadFromCSV(text)
            } else {
                BSSIDMapping.shared.loadFromData(data)
            }
        }

        statusBarController = StatusBarController()
        MappingUpdater.shared.startPeriodicFetch()
    }
}
