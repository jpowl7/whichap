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

        statusBarController = StatusBarController()
        MappingUpdater.shared.startPeriodicFetch()
    }
}
