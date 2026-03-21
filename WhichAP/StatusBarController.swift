import Cocoa

final class StatusBarController: NSObject, WiFiMonitorDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let wifiMonitor = WiFiMonitor()
    private var preferencesWindowController: PreferencesWindowController?
    private var historyWindowController: ConnectionHistoryWindowController?

    private var latestInfo: WiFiConnectionInfo?
    private var menuUpdateTimer: Timer?

    // MARK: - Persistent menu items (updated in place for live refresh)

    private let menu = NSMenu()

    private let apNameItem = NSMenuItem()
    private let locationHintItem = NSMenuItem()
    private let ssidItem = NSMenuItem()
    private let securityItem = NSMenuItem()
    private let bssidItem = NSMenuItem()
    private let signalItem = NSMenuItem()
    private let noiseItem = NSMenuItem()
    private let snrItem = NSMenuItem()
    private let bandItem = NSMenuItem()
    private let modeItem = NSMenuItem()
    private let txRateItem = NSMenuItem()
    private let ipItem = NSMenuItem()
    private let connectedTimeItem = NSMenuItem()
    private let disconnectedItem = NSMenuItem()

    private let sep1 = NSMenuItem.separator()
    private let sep2 = NSMenuItem.separator()
    private let sep3 = NSMenuItem.separator()
    private let sep4 = NSMenuItem.separator()
    private let copyItem = NSMenuItem()
    private let sep5 = NSMenuItem.separator()

    private var menuIsConnected: Bool? = nil

    // MARK: - Lifecycle

    override init() {
        super.init()

        statusItem.button?.title = "WhichAP"

        menu.autoenablesItems = false
        statusItem.menu = menu
        buildMenuStructure()
        updateMenu(with: nil)

        // Update connected time every second while menu is open
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidOpen),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidClose),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )

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
            self.updateMenu(with: info)
        }
    }

    // MARK: - Menu Open/Close (live timer)

    @objc private func menuDidOpen() {
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateConnectedTime()
        }
    }

    @objc private func menuDidClose() {
        menuUpdateTimer?.invalidate()
        menuUpdateTimer = nil
    }

    private func updateConnectedTime() {
        guard let since = wifiMonitor.connectedToAPSince else {
            connectedTimeItem.isHidden = true
            return
        }
        connectedTimeItem.isHidden = false
        let elapsed = Int(Date().timeIntervalSince(since))
        connectedTimeItem.title = "Connected: \(formatDuration(elapsed))"
    }

    // MARK: - Settings Change Handlers

    @objc private func displaySettingsChanged() {
        refreshCachedSettings()
        updateMenuBarText(with: latestInfo)
        updateMenu(with: latestInfo)
    }

    @objc private func mappingChanged() {
        refreshCachedSettings()
        updateMenuBarText(with: latestInfo)
        updateMenu(with: latestInfo)
    }

    // MARK: - AP Name Lookup

    func apName(forBSSID bssid: String) -> String? {
        return BSSIDMapping.shared.apName(forBSSID: bssid)
    }

    // MARK: - Display Settings (cached, refreshed on settings change)

    private var cachedMaxNameLength: Int = {
        let val = UserDefaults.standard.integer(forKey: "apNameMaxLength")
        return val > 0 ? val : 20
    }()

    private var cachedShowBand: Bool = {
        if UserDefaults.standard.object(forKey: "showBand") == nil { return true }
        return UserDefaults.standard.bool(forKey: "showBand")
    }()

    private func refreshCachedSettings() {
        let val = UserDefaults.standard.integer(forKey: "apNameMaxLength")
        cachedMaxNameLength = val > 0 ? val : 20
        if UserDefaults.standard.object(forKey: "showBand") == nil {
            cachedShowBand = true
        } else {
            cachedShowBand = UserDefaults.standard.bool(forKey: "showBand")
        }
    }

    // MARK: - Menu Bar Text (with change tracking)

    private var stackView: NSStackView?
    private var lastMenuBarTop: String?
    private var lastMenuBarBottom: String?
    private var lastMenuBarPoor: Bool?
    private var lastApDisplayName: String?
    private var lastSignalText: String?
    private var lastSignalPoor: Bool?

    private func updateMenuBarText(with info: WiFiConnectionInfo?) {
        guard let button = statusItem.button else { return }

        guard let info, let ssid = info.ssid else {
            removeStackView()
            button.title = "No Wi-Fi"
            button.appearsDisabled = true
            return
        }

        button.appearsDisabled = false

        let topLine = ssid
        let isPoorSignal = info.signalQuality == .poor || info.signalQuality == .bad

        // Bottom line: AP name (if available)
        let bottomLine: String?
        if let bssid = info.bssid, let name = apName(forBSSID: bssid) {
            bottomLine = truncatedName(name, limit: cachedMaxNameLength)
        } else {
            bottomLine = nil
        }

        // Skip update if nothing changed
        if topLine == lastMenuBarTop && bottomLine == lastMenuBarBottom && isPoorSignal == lastMenuBarPoor {
            return
        }
        lastMenuBarTop = topLine
        lastMenuBarBottom = bottomLine
        lastMenuBarPoor = isPoorSignal

        if let bottomLine {
            button.title = ""
            setupStackView(topLine: topLine, bottomLine: bottomLine, poorSignal: isPoorSignal, in: button)
        } else {
            removeStackView()
            if isPoorSignal {
                button.attributedTitle = NSAttributedString(string: topLine, attributes: [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.menuBarFont(ofSize: 0),
                ])
            } else {
                button.attributedTitle = NSAttributedString(string: "")
                button.title = topLine
            }
        }
    }

    private func setupStackView(topLine: String, bottomLine: String, poorSignal: Bool, in button: NSStatusBarButton) {
        let topLabel: NSTextField
        let bottomLabel: NSTextField
        let textColor: NSColor = poorSignal ? .systemRed : .controlTextColor

        if let existing = stackView {
            // Reuse existing labels
            topLabel = existing.arrangedSubviews[0] as! NSTextField
            bottomLabel = existing.arrangedSubviews[1] as! NSTextField
            topLabel.stringValue = topLine
            bottomLabel.stringValue = bottomLine
            topLabel.textColor = textColor
            bottomLabel.textColor = textColor
        } else {
            // Create new stack
            topLabel = NSTextField(labelWithString: topLine)
            topLabel.font = NSFont.menuBarFont(ofSize: 10)
            topLabel.alignment = .center
            topLabel.textColor = textColor

            bottomLabel = NSTextField(labelWithString: bottomLine)
            bottomLabel.font = NSFont.menuBarFont(ofSize: 9)
            bottomLabel.alignment = .center
            bottomLabel.textColor = textColor

            let stack = NSStackView(views: [topLabel, bottomLabel])
            stack.orientation = .vertical
            stack.spacing = -2
            stack.alignment = .centerX
            stack.translatesAutoresizingMaskIntoConstraints = false

            button.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])

            // Let the button size to fit the stack
            topLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            bottomLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            self.stackView = stack
        }

        // Update button width to fit the wider label
        let topWidth = topLabel.intrinsicContentSize.width
        let bottomWidth = bottomLabel.intrinsicContentSize.width
        let neededWidth = max(topWidth, bottomWidth) + 8
        statusItem.length = neededWidth
    }

    private func removeStackView() {
        stackView?.removeFromSuperview()
        stackView = nil
        statusItem.length = NSStatusItem.variableLength
    }

    private func truncatedName(_ name: String, limit: Int) -> String {
        guard name.count > limit else { return name }
        return "\(String(name.prefix(limit)))\u{2026}"
    }

    // MARK: - Menu Structure (built once)

    private func buildMenuStructure() {
        menu.addItem(apNameItem)
        menu.addItem(locationHintItem)
        menu.addItem(sep1)
        menu.addItem(ssidItem)
        menu.addItem(securityItem)
        menu.addItem(bssidItem)
        menu.addItem(sep2)
        menu.addItem(signalItem)
        menu.addItem(noiseItem)
        menu.addItem(snrItem)
        menu.addItem(sep3)
        menu.addItem(bandItem)
        menu.addItem(modeItem)
        menu.addItem(txRateItem)
        menu.addItem(ipItem)
        menu.addItem(connectedTimeItem)

        menu.addItem(disconnectedItem)

        menu.addItem(sep4)

        copyItem.title = "Copy Info to Clipboard"
        copyItem.action = #selector(copyToClipboard)
        copyItem.target = self
        copyItem.keyEquivalent = "c"
        menu.addItem(copyItem)
        menu.addItem(sep5)

        let historyItem = NSMenuItem(title: "Connection History\u{2026}", action: #selector(showHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

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

        locationHintItem.attributedTitle = NSAttributedString(
            string: "Enable Location Services to see AP name",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
    }

    // MARK: - Live Menu Updates

    private func updateMenu(with info: WiFiConnectionInfo?) {
        let isConnected = info?.ssid != nil

        if menuIsConnected != isConnected {
            menuIsConnected = isConnected

            apNameItem.isHidden = !isConnected
            locationHintItem.isHidden = true
            sep1.isHidden = !isConnected
            ssidItem.isHidden = !isConnected
            securityItem.isHidden = !isConnected
            bssidItem.isHidden = !isConnected
            sep2.isHidden = !isConnected
            signalItem.isHidden = !isConnected
            noiseItem.isHidden = !isConnected
            snrItem.isHidden = !isConnected
            sep3.isHidden = !isConnected
            bandItem.isHidden = !isConnected
            modeItem.isHidden = !isConnected
            txRateItem.isHidden = !isConnected
            ipItem.isHidden = !isConnected
            connectedTimeItem.isHidden = !isConnected

            disconnectedItem.isHidden = isConnected

            copyItem.isHidden = !isConnected
            sep5.isHidden = !isConnected
        }

        guard let info, let ssid = info.ssid else {
            disconnectedItem.title = "Not connected to Wi-Fi"
            return
        }

        // AP Name
        let apDisplayName: String
        if let bssid = info.bssid, let mapped = apName(forBSSID: bssid) {
            apDisplayName = mapped
        } else if info.bssid != nil {
            apDisplayName = "Unknown AP Name"
        } else {
            apDisplayName = ssid
        }
        if apDisplayName != lastApDisplayName {
            lastApDisplayName = apDisplayName
            apNameItem.attributedTitle = NSAttributedString(
                string: apDisplayName,
                attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]
            )
        }

        locationHintItem.isHidden = info.locationAuthorized

        // Network info
        ssidItem.title = "SSID: \(ssid)"
        securityItem.title = "Security: \(info.security)"
        bssidItem.title = "BSSID: \(info.bssid ?? "Unavailable")"

        // Signal quality
        let quality = info.signalQuality.rawValue
        let isPoorSignal = info.signalQuality == .poor || info.signalQuality == .bad
        let signalText = "Signal: \(info.rssi) dBm (\(quality)) — \(info.signalPercent)%"
        if signalText != lastSignalText || isPoorSignal != lastSignalPoor {
            lastSignalText = signalText
            lastSignalPoor = isPoorSignal
            if isPoorSignal {
                signalItem.attributedTitle = NSAttributedString(
                    string: signalText,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
            } else {
                signalItem.attributedTitle = nil
                signalItem.title = signalText
            }
        }
        noiseItem.title = "Noise: \(info.noise) dBm — \(info.noisePercent)%"
        snrItem.title = "SNR: \(info.snr) dB"

        // Connection details
        bandItem.title = "Band: \(info.band) | Ch \(info.channelNumber) (\(info.channelWidth))"
        modeItem.title = "Mode: \(info.phyMode)"
        txRateItem.title = "Tx Rate: \(formatTxRate(info.transmitRate)) Mbps"
        ipItem.title = "IP: \(info.ipAddress ?? "Unavailable")"

        // Connected time
        updateConnectedTime()
    }

    // MARK: - Formatting Helpers

    private func formatTxRate(_ rate: Double) -> String {
        if rate.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", rate)
        }
        return String(format: "%.1f", rate)
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }

    // MARK: - Menu Actions

    @objc private func copyToClipboard() {
        guard let info = latestInfo, let ssid = info.ssid else { return }

        let apName: String
        if let bssid = info.bssid, let mapped = self.apName(forBSSID: bssid) {
            apName = mapped
        } else {
            apName = "Unknown"
        }

        let txFormatted = formatTxRate(info.transmitRate)
        let quality = info.signalQuality.rawValue

        let text = """
        Wi-Fi Connection Info
        ─────────────────────
        AP Name:   \(apName)
        SSID:      \(ssid)
        Security:  \(info.security)
        BSSID:     \(info.bssid ?? "Unavailable")
        Signal:    \(info.rssi) dBm (\(quality)) — \(info.signalPercent)%
        Noise:     \(info.noise) dBm — \(info.noisePercent)%
        SNR:       \(info.snr) dB
        Band:      \(info.band) | Ch \(info.channelNumber) (\(info.channelWidth))
        Mode:      \(info.phyMode)
        Tx Rate:   \(txFormatted) Mbps
        IP:        \(info.ipAddress ?? "Unavailable")
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func showHistory() {
        if historyWindowController == nil {
            let controller = ConnectionHistoryWindowController()
            controller.onClear = { [weak self] in
                self?.wifiMonitor.clearHistory()
            }
            historyWindowController = controller
        }
        historyWindowController?.update(with: wifiMonitor.connectionHistory)
        historyWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

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
        alert.informativeText = """
        Version \(version) (Build \(build))

        A lightweight menu bar utility that shows which SSID and access point you are connected to (you must provide your mapping of BSSIDs to AP names).

        Clicking on the AP name provides a quick look at details of the connection, connection history, and ability to copy this info to include in a support ticket.

        App by Jason Powell
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
