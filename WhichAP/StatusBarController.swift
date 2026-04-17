import Cocoa
import CoreLocation
import CoreWLAN

final class StatusBarController: NSObject, WiFiMonitorDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let wifiMonitor = WiFiMonitor()
    private var preferencesWindowController: PreferencesWindowController?
    private var historyWindowController: ConnectionHistoryWindowController?
    private var helpWindowController: HelpWindowController?

    private var latestInfo: WiFiConnectionInfo?
    private var menuUpdateTimer: Timer?

    // MARK: - Persistent menu items (updated in place for live refresh)

    private let menu = NSMenu()

    private let apNameItem = NSMenuItem()
    private let locationHintItem = NSMenuItem()
    private let locationHeaderItem = NSMenuItem()
    private let locationExplainerItem = NSMenuItem()
    private let openLocationSettingsItem = NSMenuItem()
    private let grantLocationAccessItem = NSMenuItem()
    private let ssidItem = NSMenuItem()
    private let securityItem = NSMenuItem()
    private let bssidItem = NSMenuItem()
    private let manufacturerItem = NSMenuItem()
    private let signalItem = NSMenuItem()
    private let noiseItem = NSMenuItem()
    private let snrItem = NSMenuItem()
    private let bandItem = NSMenuItem()
    private let modeItem = NSMenuItem()
    private let txRateItem = NSMenuItem()
    private let ipItem = NSMenuItem()
    private let connectedTimeItem = NSMenuItem()
    private let uptimeItem = NSMenuItem()
    private let restartWifiItem = NSMenuItem()
    private let disconnectedItem = NSMenuItem()

    private let sep1 = NSMenuItem.separator()
    private let sep2 = NSMenuItem.separator()
    private let sep3 = NSMenuItem.separator()
    private let sep4 = NSMenuItem.separator()
    private let copyItem = NSMenuItem()
    private let sep5 = NSMenuItem.separator()

    private var currentLocationAccess: LocationAccess = .notDetermined
    private var introPanelShown = false

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
            object: menu
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidClose),
            name: NSMenu.didEndTrackingNotification,
            object: menu
        )

        wifiMonitor.delegate = self
        // Pick up the initial location state set during WiFiMonitor init
        handleLocationAccessChange(wifiMonitor.locationAccess)

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

    func wifiMonitor(_ monitor: WiFiMonitor, didChangeLocationAccess access: LocationAccess) {
        DispatchQueue.main.async { [weak self] in
            self?.handleLocationAccessChange(access)
        }
    }

    // MARK: - Location Access Handling

    private func handleLocationAccessChange(_ access: LocationAccess) {
        currentLocationAccess = access
        updateMenuBarText(with: latestInfo)
        updateMenu(with: latestInfo)

        if access == .notDetermined && !introPanelShown {
            introPanelShown = true
            DispatchQueue.main.async { [weak self] in
                self?.presentLocationIntroAndRequest()
            }
        }

        if access == .authorized {
            UserDefaults.standard.set(true, forKey: "locationPromptCompleted")
        }
    }

    private func presentLocationIntroAndRequest() {
        if UserDefaults.standard.bool(forKey: "locationPromptCompleted") {
            wifiMonitor.requestLocationPermission()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Location Access Required"
        alert.informativeText = """
        WhichAP needs Location Services permission to read your Wi-Fi connection details — this is an Apple requirement for reading SSIDs and BSSIDs on macOS.

        After you click Continue, you'll see a macOS permission prompt. Please click "Allow" to enable WhichAP.

        Your location is never stored, transmitted, or used for anything other than identifying your current Wi-Fi network.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            wifiMonitor.requestLocationPermission()
        }
    }

    @objc private func openLocationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
        NSWorkspace.shared.open(url)
    }

    @objc private func grantLocationAccess() {
        NSApp.activate(ignoringOtherApps: true)
        wifiMonitor.requestLocationPermission()
    }

    // MARK: - Menu Open/Close (live timer)

    @objc private func menuDidOpen() {
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateConnectedTime()
            self?.updateUptime()
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

        updateUptime()
    }

    private func updateUptime() {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        uptimeItem.title = "Mac Uptime: \(formatUptime(seconds))"
    }

    // MARK: - Settings Change Handlers

    @objc private func displaySettingsChanged() {
        refreshCachedSettings()
        clearMenuCache()
        updateMenuBarText(with: latestInfo)
        updateMenu(with: latestInfo)
    }

    @objc private func mappingChanged() {
        refreshCachedSettings()
        clearMenuCache()
        updateMenuBarText(with: latestInfo)
        updateMenu(with: latestInfo)
    }

    private func clearMenuCache() {
        lastMenuBarTop = nil
        lastMenuBarBottom = nil
        lastMenuBarPoor = nil
        lastApDisplayName = nil
        lastSignalText = nil
        lastSignalPoor = nil
        lastLocationAccess = nil
        lastMenuSSID = nil
        lastMenuSecurity = nil
        lastMenuBSSID = nil
        lastMenuNoise = nil
        lastMenuSNR = nil
        lastMenuBand = nil
        lastMenuMode = nil
        lastMenuTxRate = nil
        lastMenuIP = nil
        lastMenuShowConnection = nil
    }

    // MARK: - AP Name Lookup

    func apName(forBSSID bssid: String) -> String? {
        guard let fullName = BSSIDMapping.shared.apName(forBSSID: bssid) else { return nil }
        return WiFiMonitor.displayName(from: fullName)
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

    private var cachedGeekMode: Bool = {
        return UserDefaults.standard.bool(forKey: "geekMode")
    }()

    private func refreshCachedSettings() {
        let val = UserDefaults.standard.integer(forKey: "apNameMaxLength")
        cachedMaxNameLength = val > 0 ? val : 20
        if UserDefaults.standard.object(forKey: "showBand") == nil {
            cachedShowBand = true
        } else {
            cachedShowBand = UserDefaults.standard.bool(forKey: "showBand")
        }
        cachedGeekMode = UserDefaults.standard.bool(forKey: "geekMode")
    }

    // MARK: - Menu Bar Text (with change tracking)

    private var stackView: NSStackView?
    private var lastMenuBarTop: String?
    private var lastMenuBarBottom: String?
    private var lastMenuBarPoor: Bool?
    private var lastApDisplayName: String?
    private var lastSignalText: String?
    private var lastSignalPoor: Bool?
    private var lastLocationAccess: LocationAccess?

    // Change tracking for updateMenu to avoid redundant NSMenuItem property sets
    private var lastMenuSSID: String?
    private var lastMenuSecurity: String?
    private var lastMenuBSSID: String?
    private var lastMenuNoise: String?
    private var lastMenuSNR: String?
    private var lastMenuBand: String?
    private var lastMenuMode: String?
    private var lastMenuTxRate: String?
    private var lastMenuIP: String?
    private var lastMenuShowConnection: Bool?

    private func updateMenuBarText(with info: WiFiConnectionInfo?) {
        guard let button = statusItem.button else { return }

        // Location permission states take precedence over connection state
        switch currentLocationAccess {
        case .denied, .restricted, .systemDisabled:
            removeStackView()
            button.appearsDisabled = false
            button.attributedTitle = NSAttributedString(string: "\u{26A0} Location Off", attributes: [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.menuBarFont(ofSize: 0),
            ])
            lastMenuBarTop = nil
            lastMenuBarBottom = nil
            lastMenuBarPoor = nil
            return
        case .notDetermined:
            removeStackView()
            button.appearsDisabled = true
            button.attributedTitle = NSAttributedString(string: "")
            button.title = "WhichAP"
            lastMenuBarTop = nil
            lastMenuBarBottom = nil
            lastMenuBarPoor = nil
            return
        case .authorized:
            break
        }

        guard let info, let ssid = info.ssid else {
            removeStackView()
            button.attributedTitle = NSAttributedString(string: "")
            button.title = "No Wi-Fi"
            button.appearsDisabled = true
            // Clear cached state so reconnect triggers a full update
            lastMenuBarTop = nil
            lastMenuBarBottom = nil
            lastMenuBarPoor = nil
            return
        }

        button.appearsDisabled = false

        let isPoorSignal = info.signalQuality == .poor || info.signalQuality == .bad

        let topLine: String
        let bottomLine: String?

        if cachedGeekMode {
            // Geek mode: "SSID > AP Name" on top, "Signal%|Band|chN" on bottom
            let apDisplayName: String?
            if let bssid = info.bssid, let name = self.apName(forBSSID: bssid) {
                apDisplayName = truncatedName(name, limit: cachedMaxNameLength)
            } else {
                apDisplayName = nil
            }

            if let apDisplayName {
                topLine = "\(ssid)\u{2009}:\u{2009}\(apDisplayName)"
            } else {
                topLine = ssid
            }
            let compactBand = info.band.replacingOccurrences(of: " ", with: "")
            bottomLine = "\(info.signalPercent)%|\(compactBand)|ch\(info.channelNumber)"
        } else {
            // Normal mode: SSID on top, AP name on bottom
            topLine = ssid
            if let bssid = info.bssid, let name = apName(forBSSID: bssid) {
                bottomLine = truncatedName(name, limit: cachedMaxNameLength)
            } else {
                bottomLine = nil
            }
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

    private let copyHintItem = NSMenuItem()

    private func buildMenuStructure() {
        menu.addItem(apNameItem)

        restartWifiItem.title = "Restart Wi-Fi"
        restartWifiItem.action = #selector(restartWifi)
        restartWifiItem.target = self
        restartWifiItem.keyEquivalent = "r"
        menu.addItem(restartWifiItem)

        let wifiSettingsItem = NSMenuItem(title: "Wi-Fi Settings\u{2026}", action: #selector(openWifiSettings), keyEquivalent: "w")
        wifiSettingsItem.target = self
        menu.addItem(wifiSettingsItem)

        menu.addItem(uptimeItem)

        // Location permission UI (shown only when location is denied/restricted/notDetermined)
        locationHeaderItem.attributedTitle = NSAttributedString(
            string: "Location Access Required",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.systemRed,
            ]
        )
        menu.addItem(locationHeaderItem)

        locationExplainerItem.attributedTitle = NSAttributedString(
            string: "WhichAP needs Location Services to read\nyour Wi-Fi SSID and AP details.",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        menu.addItem(locationExplainerItem)

        openLocationSettingsItem.attributedTitle = NSAttributedString(
            string: "Open Location Settings\u{2026}",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.systemBlue,
            ]
        )
        openLocationSettingsItem.action = #selector(openLocationSettings)
        openLocationSettingsItem.target = self
        menu.addItem(openLocationSettingsItem)

        grantLocationAccessItem.attributedTitle = NSAttributedString(
            string: "Grant Location Access\u{2026}",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.systemBlue,
            ]
        )
        grantLocationAccessItem.action = #selector(grantLocationAccess)
        grantLocationAccessItem.target = self
        menu.addItem(grantLocationAccessItem)

        menu.addItem(locationHintItem)

        // Copy hint
        copyHintItem.attributedTitle = NSAttributedString(
            string: "Click any item to copy",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
        menu.addItem(copyHintItem)

        menu.addItem(sep1)

        // Make all info items clickable to copy
        let copyableItems = [ssidItem, securityItem, bssidItem, manufacturerItem, signalItem, noiseItem,
                             snrItem, bandItem, modeItem, txRateItem, ipItem, connectedTimeItem, uptimeItem]
        for item in copyableItems {
            item.target = self
            item.action = #selector(copyItemValue(_:))
        }
        apNameItem.target = self
        apNameItem.action = #selector(copyItemValue(_:))

        menu.addItem(ssidItem)
        menu.addItem(securityItem)
        menu.addItem(bssidItem)
        menu.addItem(manufacturerItem)
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

        copyItem.title = "Copy All to Clipboard"
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

        let helpItem = NSMenuItem(title: "Help", action: #selector(showHelp), keyEquivalent: "?")
        helpItem.target = self
        menu.addItem(helpItem)

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
        let locationSystemOff = currentLocationAccess == .systemDisabled
        let locationBlocked = currentLocationAccess == .denied || currentLocationAccess == .restricted
        let locationPending = currentLocationAccess == .notDetermined
        let locationUnavailable = locationSystemOff || locationBlocked || locationPending
        let showConnectionInfo = isConnected && currentLocationAccess == .authorized

        // Only update location section and visibility when state actually changes
        if currentLocationAccess != lastLocationAccess || showConnectionInfo != (lastMenuShowConnection ?? false) {
            lastLocationAccess = currentLocationAccess
            lastMenuShowConnection = showConnectionInfo

            locationHeaderItem.isHidden = !locationUnavailable
            locationExplainerItem.isHidden = !locationUnavailable
            openLocationSettingsItem.isHidden = !(locationBlocked || locationSystemOff)
            grantLocationAccessItem.isHidden = !locationPending

            if locationSystemOff {
                locationHeaderItem.attributedTitle = NSAttributedString(
                    string: "Location Services Disabled",
                    attributes: [
                        .font: NSFont.boldSystemFont(ofSize: 13),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                )
                locationExplainerItem.attributedTitle = NSAttributedString(
                    string: "Location Services is turned off system-wide.\nOpen Settings and turn on Location Services\nat the top of the list.",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                )
            } else if locationBlocked {
                locationHeaderItem.attributedTitle = NSAttributedString(
                    string: "Location Access Required",
                    attributes: [
                        .font: NSFont.boldSystemFont(ofSize: 13),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                )
                locationExplainerItem.attributedTitle = NSAttributedString(
                    string: "Find WhichAP in Location Services\nand toggle it on.",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                )
            } else if locationPending {
                locationHeaderItem.attributedTitle = NSAttributedString(
                    string: "Location Permission Needed",
                    attributes: [
                        .font: NSFont.boldSystemFont(ofSize: 13),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                )
                locationExplainerItem.attributedTitle = NSAttributedString(
                    string: "Click below to grant location access.",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                )
            }

            apNameItem.isHidden = !showConnectionInfo
            restartWifiItem.isHidden = !showConnectionInfo
            locationHintItem.isHidden = true
            copyHintItem.isHidden = !showConnectionInfo
            sep1.isHidden = !showConnectionInfo
            ssidItem.isHidden = !showConnectionInfo
            securityItem.isHidden = !showConnectionInfo
            bssidItem.isHidden = !showConnectionInfo
            manufacturerItem.isHidden = !showConnectionInfo
            sep2.isHidden = !showConnectionInfo
            signalItem.isHidden = !showConnectionInfo
            noiseItem.isHidden = !showConnectionInfo
            snrItem.isHidden = !showConnectionInfo
            sep3.isHidden = !showConnectionInfo
            bandItem.isHidden = !showConnectionInfo
            modeItem.isHidden = !showConnectionInfo
            txRateItem.isHidden = !showConnectionInfo
            ipItem.isHidden = !showConnectionInfo
            connectedTimeItem.isHidden = !showConnectionInfo
            disconnectedItem.isHidden = showConnectionInfo || locationUnavailable
            copyItem.isHidden = !showConnectionInfo
            sep5.isHidden = !showConnectionInfo
        }

        guard showConnectionInfo, let info, let ssid = info.ssid else {
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
            let apTitle = "AP Name: \(apDisplayName)"
            apNameItem.title = apTitle
            apNameItem.attributedTitle = NSAttributedString(
                string: apTitle,
                attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]
            )
        }

        // Network info — only set when values change
        let ssidText = "SSID: \(ssid)"
        if ssidText != lastMenuSSID {
            lastMenuSSID = ssidText
            ssidItem.title = ssidText
        }

        let securityText = "Security: \(info.security)"
        if securityText != lastMenuSecurity {
            lastMenuSecurity = securityText
            securityItem.title = securityText
        }

        let bssidText = "BSSID: \(info.bssid ?? "Unavailable")"
        if bssidText != lastMenuBSSID {
            lastMenuBSSID = bssidText
            bssidItem.title = bssidText
        }

        // Manufacturer lookup runs outside BSSID change guard so failed
        // lookups retry on subsequent polls. OUILookup returns from its
        // in-memory cache instantly when the OUI is already known, so
        // this is only expensive on the first successful fetch.
        if let bssid = info.bssid {
            OUILookup.shared.manufacturer(forBSSID: bssid) { [weak self] mfr in
                let text = "Manufacturer: \(mfr ?? "Unknown")"
                DispatchQueue.main.async {
                    guard self?.manufacturerItem.title != text else { return }
                    self?.manufacturerItem.title = text
                }
            }
        }

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

        let noiseText = "Noise: \(info.noise) dBm — \(info.noisePercent)%"
        if noiseText != lastMenuNoise {
            lastMenuNoise = noiseText
            noiseItem.title = noiseText
        }

        let snrText = "SNR: \(info.snr) dB"
        if snrText != lastMenuSNR {
            lastMenuSNR = snrText
            snrItem.title = snrText
        }

        let bandText = "Band: \(info.band) | Ch \(info.channelNumber) (\(info.channelWidth))"
        if bandText != lastMenuBand {
            lastMenuBand = bandText
            bandItem.title = bandText
        }

        let modeText = "Mode: \(info.phyMode)"
        if modeText != lastMenuMode {
            lastMenuMode = modeText
            modeItem.title = modeText
        }

        let txText = "Tx Rate: \(formatTxRate(info.transmitRate)) Mbps"
        if txText != lastMenuTxRate {
            lastMenuTxRate = txText
            txRateItem.title = txText
        }

        let ipText = "IP: \(info.ipAddress ?? "Unavailable")"
        if ipText != lastMenuIP {
            lastMenuIP = ipText
            ipItem.title = ipText
        }

        // Uptime and connected time — these always change (time-based) but only
        // modify dropdown menu items, not the status bar button, so they don't
        // trigger the expensive NSStatusItem _updateReplicants redraw.
        updateUptime()
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

    private func formatUptime(_ totalSeconds: Int) -> String {
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    // MARK: - Menu Actions

    @objc private func copyItemValue(_ sender: NSMenuItem) {
        // Extract the value after the label prefix (e.g. "SSID: foo" → "foo")
        let text = sender.title
        let value: String
        if let colonRange = text.range(of: ": ") {
            value = String(text[colonRange.upperBound...])
        } else {
            value = text
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

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

        let uptimeSeconds = Int(ProcessInfo.processInfo.systemUptime)
        let uptimeFormatted = formatUptime(uptimeSeconds)

        let text = """
        Wi-Fi Connection Info
        ─────────────────────
        AP Name:   \(apName)
        SSID:      \(ssid)
        Security:  \(info.security)
        BSSID:     \(info.bssid ?? "Unavailable")
        Mfr:       \(manufacturerItem.title.replacingOccurrences(of: "Manufacturer: ", with: ""))
        Signal:    \(info.rssi) dBm (\(quality)) — \(info.signalPercent)%
        Noise:     \(info.noise) dBm — \(info.noisePercent)%
        SNR:       \(info.snr) dB
        Band:      \(info.band) | Ch \(info.channelNumber) (\(info.channelWidth))
        Mode:      \(info.phyMode)
        Tx Rate:   \(txFormatted) Mbps
        IP:        \(info.ipAddress ?? "Unavailable")
        Mac Uptime: \(uptimeFormatted)
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

    @objc private func showHelp() {
        if helpWindowController == nil {
            helpWindowController = HelpWindowController()
        }
        helpWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"

        let text = """
        Version \(version) (Build \(build))

        A lightweight menu bar utility that shows which SSID and access point you are connected to (you must provide your mapping of BSSIDs to AP names).

        Clicking on the AP name provides a quick look at details of the connection, connection history, and ability to copy this info to include in a support ticket.

        \u{00A9} 2026 Jason Powell. All rights reserved.
        venmo: @jasonpowell7 if you'd like to buy me a beverage ;-)
        """

        let alert = NSAlert()
        alert.messageText = "WhichAP"
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func restartWifi() {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        do {
            try interface.setPower(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                do {
                    try interface.setPower(true)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Failed to re-enable Wi-Fi"
                    alert.informativeText = "Wi-Fi was turned off but could not be turned back on. Please re-enable it manually.\n\n\(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        } catch {
            // Power-off failed — Wi-Fi is still on, no action needed
        }
    }

    @objc private func openWifiSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
