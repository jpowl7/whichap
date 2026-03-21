import Cocoa

final class StatusBarController: NSObject, WiFiMonitorDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let wifiMonitor = WiFiMonitor()
    private var preferencesWindowController: PreferencesWindowController?

    private var latestInfo: WiFiConnectionInfo?

    // MARK: - Lifecycle

    override init() {
        super.init()

        statusItem.button?.title = "WhichAP"
        rebuildMenu(with: nil)

        wifiMonitor.delegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaySettingsChanged),
            name: Notification.Name("DisplaySettingsChanged"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mappingChanged),
            name: Notification.Name("MappingSourceChanged"),
            object: nil
        )
    }

    // MARK: - WiFiMonitorDelegate

    func wifiMonitor(_ monitor: WiFiMonitor, didUpdateConnection info: WiFiConnectionInfo?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestInfo = info
            self.updateMenuBarText(with: info)
            self.rebuildMenu(with: info)
        }
    }

    // MARK: - Settings Change Handlers

    @objc private func displaySettingsChanged() {
        updateMenuBarText(with: latestInfo)
        rebuildMenu(with: latestInfo)
    }

    @objc private func mappingChanged() {
        updateMenuBarText(with: latestInfo)
        rebuildMenu(with: latestInfo)
    }

    // MARK: - AP Name Lookup

    func apName(forBSSID bssid: String) -> String? {
        return BSSIDMapping.shared.apName(forBSSID: bssid)
    }

    // MARK: - Display Settings

    private var maxNameLength: Int {
        let val = UserDefaults.standard.integer(forKey: "apNameMaxLength")
        return val > 0 ? val : 20
    }

    private var showBand: Bool {
        if UserDefaults.standard.object(forKey: "showBand") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "showBand")
    }

    // MARK: - Menu Bar Text

    private func updateMenuBarText(with info: WiFiConnectionInfo?) {
        guard let button = statusItem.button else { return }

        guard let info, let ssid = info.ssid else {
            button.title = "No Wi-Fi"
            button.appearsDisabled = true
            return
        }

        button.appearsDisabled = false

        if let bssid = info.bssid, let name = apName(forBSSID: bssid) {
            let displayName = truncatedName(name, limit: maxNameLength)
            if showBand {
                button.title = "\(displayName) | \(info.band)"
            } else {
                button.title = displayName
            }
        } else if !info.locationAuthorized {
            // No location permission — show SSID only (no band), per PRD
            button.title = ssid
        } else {
            // BSSID available but not in mapping — show SSID with band
            if showBand {
                button.title = "\(ssid) | \(info.band)"
            } else {
                button.title = ssid
            }
        }
    }

    private func truncatedName(_ name: String, limit: Int) -> String {
        guard name.count > limit else { return name }
        return "\(String(name.prefix(limit)))\u{2026}"
    }

    // MARK: - Dropdown Menu

    private func rebuildMenu(with info: WiFiConnectionInfo?) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let info, let ssid = info.ssid {
            // AP Name
            let apDisplayName: String
            if let bssid = info.bssid, let mapped = apName(forBSSID: bssid) {
                apDisplayName = mapped
            } else if info.bssid != nil {
                apDisplayName = "Unknown AP"
            } else {
                apDisplayName = ssid
            }
            menu.addItem(disabledItem(apDisplayName))

            // Location permission hint
            if !info.locationAuthorized {
                let hint = disabledItem("Enable Location Services to see AP name")
                hint.attributedTitle = NSAttributedString(
                    string: hint.title,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                )
                menu.addItem(hint)
            }

            // SSID
            menu.addItem(disabledItem("SSID: \(ssid)"))

            // Band / Channel
            menu.addItem(disabledItem("Band: \(info.band) | Ch \(info.channelNumber) (\(info.channelWidth))"))

            // BSSID
            menu.addItem(disabledItem("BSSID: \(info.bssid ?? "Unavailable")"))

            // Signal
            let quality = info.signalQuality.rawValue
            menu.addItem(disabledItem("Signal: \(info.rssi) dBm (\(quality))"))

            // SNR
            menu.addItem(disabledItem("SNR: \(info.snr) dB"))

            // Tx Rate
            let txFormatted = formatTxRate(info.transmitRate)
            menu.addItem(disabledItem("Tx: \(txFormatted) Mbps"))
        } else {
            menu.addItem(disabledItem("Not connected to Wi-Fi"))
        }

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences\u{2026}", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let aboutItem = NSMenuItem(title: "About WhichAP", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit WhichAP", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        return item
    }

    // MARK: - Formatting Helpers

    private func formatTxRate(_ rate: Double) -> String {
        if rate.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", rate)
        }
        return String(format: "%.1f", rate)
    }

    // MARK: - Menu Actions

    @objc private func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow(nil)
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"

        let alert = NSAlert()
        alert.messageText = "WhichAP"
        alert.informativeText = "Version \(version) (Build \(build))\n\nA lightweight menu bar utility that shows which access point you are connected to."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
