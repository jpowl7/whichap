import Cocoa
import CoreWLAN
import ServiceManagement
import UserNotifications

// MARK: - UserDefaults Keys

private enum PrefKey {
    static let mappingSource     = "mappingSource"
    static let mappingFilePath   = "mappingFilePath"
    static let mappingURL        = "mappingURL"
    static let fetchInterval     = "fetchInterval"
    static let apNameMaxLength   = "apNameMaxLength"
    static let showBand          = "showBand"
    static let truncateAtColon   = "truncateAtColon"
    static let geekMode          = "geekMode"
    static let launchAtLogin     = "launchAtLogin"
    static let notifyOnRoam      = "notifyOnRoam"
    static let notifyMode        = "notifyMode"
    static let signalPercentStyle = "signalPercentStyle"
}

// MARK: - PreferencesWindowController

final class PreferencesWindowController: NSWindowController {

    // MARK: Controls

    private var sourcePopUp:      NSPopUpButton!
    private var filePathLabel:    NSTextField!
    private var chooseFileButton: NSButton!
    private var urlField:         NSTextField!
    private var intervalPopUp:    NSPopUpButton!
    private var maxLengthStepper: NSStepper!
    private var maxLengthLabel:   NSTextField!
    private var truncateCheckbox: NSButton!
    private var geekModeCheckbox: NSButton!
    private var launchCheckbox:   NSButton!
    private var signalStylePopUp: NSPopUpButton!

    // Notifications section
    private var notifyCheckbox:   NSButton!
    private var notifyModePopUp:  NSPopUpButton!
    private var notifyTestButton: NSButton!
    private var notifyStatusLabel: NSTextField!

    // Manual entry controls
    private var mappingEditorController: MappingEditorWindowController?
    private var manualApNameField:  NSTextField!
    private var manualBssidField:   NSTextField!
    private var addEntryButton:     NSButton!
    private var manualCountLabel:   NSTextField!

    // Conditional rows
    private var fileRow:       NSView!
    private var urlRow:        NSView!
    private var intervalRow:   NSView!
    private var formatHintRow: NSView!

    // Layout
    private var stackView: NSStackView!

    // MARK: Geometry

    private let windowWidth: CGFloat = 340
    private let contentInset: CGFloat = 20

    // MARK: Lifecycle

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WhichAP Preferences"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = .moveToActiveSpace

        self.init(window: window)

        buildUI()
        loadCurrentValues()
        updateConditionalVisibility(animated: false)

        // Re-check notification permission whenever the Preferences window
        // regains focus. Catches the common path of user toggling settings in
        // System Settings and coming back here expecting the inline status
        // label to reflect the new state.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKeyHandler),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
    }

    @objc private func windowDidBecomeKeyHandler() {
        refreshNotifyAuthStatus()
    }

    override func showWindow(_ sender: Any?) {
        if let bssid = CWWiFiClient.shared().interface()?.bssid() {
            manualBssidField.stringValue = bssid.split(separator: ":")
                .map { octet -> String in
                    let hex = String(octet).uppercased()
                    return hex.count == 1 ? "0\(hex)" : hex
                }
                .joined(separator: ":")
        }
        updateManualCount()
        sizeWindowToFit()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let window = window else { return }

        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: contentInset, left: contentInset, bottom: contentInset, right: contentInset)

        let clipView = scrollView.contentView
        scrollView.documentView = stackView

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
        ])

        window.contentView = scrollView

        let fieldWidth = windowWidth - contentInset * 2

        // ── Mapping Source ─────────────────────────────────────────

        stackView.addArrangedSubview(makeSectionLabel("Mapping Source"))

        sourcePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        sourcePopUp.addItems(withTitles: ["Bundled", "File", "URL"])
        sourcePopUp.target = self
        sourcePopUp.action = #selector(mappingSourceChanged(_:))
        addWidthConstraint(sourcePopUp, width: fieldWidth)
        stackView.addArrangedSubview(sourcePopUp)

        // File row
        fileRow = makeInlineRow {
            self.filePathLabel = NSTextField(labelWithString: "None selected")
            self.filePathLabel.lineBreakMode = .byTruncatingMiddle
            self.filePathLabel.textColor = .secondaryLabelColor
            self.filePathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            self.filePathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            self.chooseFileButton = NSButton(title: "Choose\u{2026}", target: self, action: #selector(self.chooseFile(_:)))
            self.chooseFileButton.bezelStyle = .rounded
            self.chooseFileButton.setContentHuggingPriority(.required, for: .horizontal)

            let row = NSStackView(views: [self.filePathLabel, self.chooseFileButton])
            row.orientation = .horizontal
            row.spacing = 8
            self.addWidthConstraint(row, width: fieldWidth)
            return row
        }
        stackView.addArrangedSubview(fileRow)

        // URL row
        urlRow = makeInlineRow {
            self.urlField = NSTextField(frame: .zero)
            self.urlField.placeholderString = "https://example.com/mapping.json"
            self.urlField.target = self
            self.urlField.action = #selector(self.urlChanged(_:))
            self.addWidthConstraint(self.urlField, width: fieldWidth)
            return self.urlField
        }
        stackView.addArrangedSubview(urlRow)

        // Fetch interval row
        intervalRow = makeInlineRow {
            let label = self.makeFieldLabel("Refresh")
            self.intervalPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
            self.intervalPopUp.addItems(withTitles: ["Hourly", "Daily", "Weekly"])
            self.intervalPopUp.target = self
            self.intervalPopUp.action = #selector(self.fetchIntervalChanged(_:))
            let row = NSStackView(views: [label, self.intervalPopUp])
            row.orientation = .horizontal
            row.spacing = 6
            return row
        }
        stackView.addArrangedSubview(intervalRow)

        // Format hint
        formatHintRow = makeInlineRow {
            let hint = NSTextField(wrappingLabelWithString:
                "JSON with \"apName\" and \"bssid\" fields, CSV with apName,bssid columns, or Ruckus Data Studio exports.")
            hint.font = NSFont.systemFont(ofSize: 10)
            hint.textColor = .tertiaryLabelColor
            hint.isSelectable = false
            self.addWidthConstraint(hint, width: fieldWidth)
            return hint
        }
        stackView.addArrangedSubview(formatHintRow)

        // ── Separator ──────────────────────────────────────────────

        stackView.addArrangedSubview(makeSeparator(width: fieldWidth))

        // ── Manual Entry ───────────────────────────────────────────

        stackView.addArrangedSubview(makeSectionLabel("Add AP Mapping"))

        // AP Name
        stackView.addArrangedSubview(makeFieldLabel("AP Name"))
        manualApNameField = NSTextField(frame: .zero)
        manualApNameField.placeholderString = "e.g. Lobby North"
        addWidthConstraint(manualApNameField, width: fieldWidth)
        stackView.addArrangedSubview(manualApNameField)

        // BSSID
        stackView.addArrangedSubview(makeFieldLabel("Current BSSID"))
        manualBssidField = NSTextField(frame: .zero)
        manualBssidField.placeholderString = "e.g. 00:33:58:A9:B5:F0"
        addWidthConstraint(manualBssidField, width: fieldWidth)
        stackView.addArrangedSubview(manualBssidField)

        // Add button + count
        addEntryButton = NSButton(title: "Add Mapping", target: self, action: #selector(addManualEntry(_:)))
        addEntryButton.bezelStyle = .rounded
        manualCountLabel = NSTextField(labelWithString: "")
        manualCountLabel.font = NSFont.systemFont(ofSize: 10)
        manualCountLabel.textColor = .tertiaryLabelColor
        let addRow = NSStackView(views: [addEntryButton, manualCountLabel])
        addRow.orientation = .horizontal
        addRow.spacing = 8
        stackView.addArrangedSubview(addRow)

        // View & Edit Mappings
        let editBtn = NSButton(title: "View & Edit Mappings\u{2026}", target: self, action: #selector(showMappingEditor))
        editBtn.bezelStyle = .rounded
        stackView.addArrangedSubview(editBtn)

        // ── Separator ──────────────────────────────────────────────

        stackView.addArrangedSubview(makeSeparator(width: fieldWidth))

        // ── Display ────────────────────────────────────────────────

        stackView.addArrangedSubview(makeSectionLabel("Display"))

        // Max length
        maxLengthLabel = NSTextField(labelWithString: "20")
        maxLengthLabel.alignment = .center
        maxLengthLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        addWidthConstraint(maxLengthLabel, width: 28)
        maxLengthStepper = NSStepper(frame: .zero)
        maxLengthStepper.minValue = 5
        maxLengthStepper.maxValue = 50
        maxLengthStepper.increment = 1
        maxLengthStepper.valueWraps = false
        maxLengthStepper.target = self
        maxLengthStepper.action = #selector(maxLengthChanged(_:))
        let maxLenLabel = makeFieldLabel("AP name max length")
        let maxLenRow = NSStackView(views: [maxLenLabel, maxLengthLabel, maxLengthStepper])
        maxLenRow.orientation = .horizontal
        maxLenRow.spacing = 4
        stackView.addArrangedSubview(maxLenRow)

        // Truncate
        truncateCheckbox = NSButton(checkboxWithTitle: "Truncate AP name at \":\"", target: self, action: #selector(truncateAtColonChanged(_:)))
        truncateCheckbox.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        stackView.addArrangedSubview(truncateCheckbox)

        // Geek mode
        geekModeCheckbox = NSButton(checkboxWithTitle: "Geek mode (signal, band, channel)", target: self, action: #selector(geekModeChanged(_:)))
        geekModeCheckbox.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        stackView.addArrangedSubview(geekModeCheckbox)

        // Signal % style
        stackView.addArrangedSubview(makeFieldLabel("Signal % style"))
        signalStylePopUp = NSPopUpButton()
        signalStylePopUp.addItems(withTitles: ["Standard (clamped -37 → -100 dBm)", "Lenient (linear -50 → -100 dBm)"])
        signalStylePopUp.target = self
        signalStylePopUp.action = #selector(signalStyleChanged(_:))
        addWidthConstraint(signalStylePopUp, width: fieldWidth)
        stackView.addArrangedSubview(signalStylePopUp)

        // ── Separator ──────────────────────────────────────────────

        stackView.addArrangedSubview(makeSeparator(width: fieldWidth))

        // ── General ────────────────────────────────────────────────

        launchCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(launchAtLoginChanged(_:)))
        launchCheckbox.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        stackView.addArrangedSubview(launchCheckbox)

        // ── Separator ──────────────────────────────────────────────

        stackView.addArrangedSubview(makeSeparator(width: fieldWidth))

        // ── Notifications ──────────────────────────────────────────

        stackView.addArrangedSubview(makeSectionLabel("Notifications"))

        notifyCheckbox = NSButton(checkboxWithTitle: "Notify on roam events", target: self, action: #selector(notifyEnabledChanged(_:)))
        notifyCheckbox.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        stackView.addArrangedSubview(notifyCheckbox)

        let notifyModeLabel = makeFieldLabel("Notify for")
        stackView.addArrangedSubview(notifyModeLabel)

        notifyModePopUp = NSPopUpButton()
        notifyModePopUp.addItems(withTitles: ["Problems only", "All roams"])
        notifyModePopUp.target = self
        notifyModePopUp.action = #selector(notifyModeChanged(_:))
        addWidthConstraint(notifyModePopUp, width: fieldWidth)
        stackView.addArrangedSubview(notifyModePopUp)

        notifyTestButton = NSButton(title: "Test Notification", target: self, action: #selector(sendTestNotification(_:)))
        stackView.addArrangedSubview(notifyTestButton)

        notifyStatusLabel = NSTextField(labelWithString: "")
        notifyStatusLabel.font = NSFont.systemFont(ofSize: 11)
        notifyStatusLabel.textColor = .systemRed
        notifyStatusLabel.lineBreakMode = .byWordWrapping
        notifyStatusLabel.maximumNumberOfLines = 3
        notifyStatusLabel.isHidden = true
        addWidthConstraint(notifyStatusLabel, width: fieldWidth)
        stackView.addArrangedSubview(notifyStatusLabel)
    }

    // MARK: - Helpers: View creation

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeSeparator(width: CGFloat) -> NSView {
        let sep = NSBox()
        sep.boxType = .separator
        addWidthConstraint(sep, width: width)
        return sep
    }

    private func makeInlineRow(_ builder: () -> NSView) -> NSView {
        return builder()
    }

    private func addWidthConstraint(_ view: NSView, width: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func sizeWindowToFit() {
        guard let window = window else { return }
        stackView.layoutSubtreeIfNeeded()
        let fittingSize = stackView.fittingSize
        let maxH: CGFloat = 600
        let h = min(fittingSize.height, maxH)
        let frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: windowWidth, height: h))
        let currentFrame = window.frame
        let newOrigin = NSPoint(x: currentFrame.midX - frame.width / 2,
                                y: currentFrame.maxY - frame.height)
        window.setFrame(NSRect(origin: newOrigin, size: frame.size), display: true, animate: false)
    }

    // MARK: - Load Stored Values

    private func loadCurrentValues() {
        let defaults = UserDefaults.standard

        defaults.register(defaults: [
            PrefKey.mappingSource:   "bundled",
            PrefKey.mappingURL:      "",
            PrefKey.fetchInterval:   "daily",
            PrefKey.apNameMaxLength: 20,
            PrefKey.showBand:        true,
            PrefKey.launchAtLogin:   true,
        ])

        let source = defaults.string(forKey: PrefKey.mappingSource) ?? "bundled"
        switch source {
        case "file": sourcePopUp.selectItem(withTitle: "File")
        case "url":  sourcePopUp.selectItem(withTitle: "URL")
        default:     sourcePopUp.selectItem(withTitle: "Bundled")
        }

        if let path = defaults.string(forKey: PrefKey.mappingFilePath), !path.isEmpty {
            filePathLabel.stringValue = (path as NSString).lastPathComponent
            filePathLabel.toolTip = path
        }

        urlField.stringValue = defaults.string(forKey: PrefKey.mappingURL) ?? ""

        let interval = defaults.string(forKey: PrefKey.fetchInterval) ?? "daily"
        switch interval {
        case "hourly":  intervalPopUp.selectItem(withTitle: "Hourly")
        case "weekly":  intervalPopUp.selectItem(withTitle: "Weekly")
        default:        intervalPopUp.selectItem(withTitle: "Daily")
        }

        let maxLen = defaults.integer(forKey: PrefKey.apNameMaxLength)
        let clampedMaxLen = max(5, min(50, maxLen == 0 ? 20 : maxLen))
        maxLengthStepper.integerValue = clampedMaxLen
        maxLengthLabel.stringValue = "\(clampedMaxLen)"

        truncateCheckbox.state = defaults.bool(forKey: PrefKey.truncateAtColon) ? .on : .off
        geekModeCheckbox.state = defaults.bool(forKey: PrefKey.geekMode) ? .on : .off

        let style = defaults.string(forKey: PrefKey.signalPercentStyle) ?? "standard"
        signalStylePopUp.selectItem(withTitle: style == "lenient"
            ? "Lenient (linear -50 → -100 dBm)"
            : "Standard (clamped -37 → -100 dBm)")

        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            launchCheckbox.state = (status == .enabled) ? .on : .off
        }

        let notifyEnabled = defaults.bool(forKey: PrefKey.notifyOnRoam)
        notifyCheckbox.state = notifyEnabled ? .on : .off
        let mode = defaults.string(forKey: PrefKey.notifyMode) ?? "problemsOnly"
        notifyModePopUp.selectItem(withTitle: mode == "all" ? "All roams" : "Problems only")
        applyNotifyControlsEnabled(notifyEnabled)
        refreshNotifyAuthStatus()

        updateManualCount()
    }

    /// Reflects current macOS authorization in the inline status label so the
    /// user knows why notifications aren't arriving even when the toggle is on.
    /// Catches the common pitfall where authorization is granted but alert
    /// style is "None", which silently routes alerts to Notification Center
    /// only — no banners appear.
    private func refreshNotifyAuthStatus() {
        guard notifyCheckbox.state == .on else {
            notifyStatusLabel.isHidden = true
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let (message, isWarning) = self.statusMessage(for: settings)
                if let message = message {
                    self.notifyStatusLabel.stringValue = message
                    self.notifyStatusLabel.textColor = isWarning ? .systemRed : .secondaryLabelColor
                    self.notifyStatusLabel.isHidden = false
                } else {
                    self.notifyStatusLabel.isHidden = true
                }
                self.sizeWindowToFit()
            }
        }
    }

    private func statusMessage(for settings: UNNotificationSettings) -> (String?, Bool) {
        switch settings.authorizationStatus {
        case .denied:
            return ("Notifications denied. Open System Settings → Notifications → WhichAP and turn on \"Allow notifications\".", true)
        case .notDetermined:
            return ("Permission not yet requested. Toggle the checkbox to prompt.", true)
        case .authorized, .provisional, .ephemeral:
            // Authorized — but check whether banners will actually appear.
            if settings.alertSetting == .disabled {
                return ("Authorized but alerts are off. Open System Settings → Notifications → WhichAP and re-enable \"Allow notifications\".", true)
            }
            if settings.alertStyle == .none {
                return ("Authorized but alert style is None. Open System Settings → Notifications → WhichAP and set Alert Style to Banners or Alerts.", true)
            }
            return (nil, false)
        @unknown default:
            return (nil, false)
        }
    }

    private func applyNotifyControlsEnabled(_ enabled: Bool) {
        notifyModePopUp.isEnabled = enabled
        notifyTestButton.isEnabled = enabled
    }

    // MARK: - Conditional Visibility

    private func updateConditionalVisibility(animated: Bool) {
        let source = selectedSourceValue()

        fileRow.isHidden       = (source != "file")
        urlRow.isHidden        = (source != "url")
        intervalRow.isHidden   = (source != "url")
        formatHintRow.isHidden = (source == "bundled")

        sizeWindowToFit()
    }

    private func selectedSourceValue() -> String {
        switch sourcePopUp.titleOfSelectedItem {
        case "File": return "file"
        case "URL":  return "url"
        default:     return "bundled"
        }
    }

    private func selectedIntervalValue() -> String {
        switch intervalPopUp.titleOfSelectedItem {
        case "Hourly": return "hourly"
        case "Weekly": return "weekly"
        default:       return "daily"
        }
    }

    // MARK: - Actions

    @objc private func mappingSourceChanged(_ sender: NSPopUpButton) {
        let value = selectedSourceValue()
        UserDefaults.standard.set(value, forKey: PrefKey.mappingSource)
        updateConditionalVisibility(animated: true)
        NotificationCenter.default.post(name: Notification.Name("MappingSourceChanged"), object: nil)
    }

    @objc private func chooseFile(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.title = "Choose Mapping File"
        panel.allowedContentTypes = [
            .init(filenameExtension: "json")!,
            .init(filenameExtension: "csv")!,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            handleSelectedFile(url)
        }
    }

    private func handleSelectedFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()

        // Store a security-scoped bookmark so the sandbox allows access after reboot
        if let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmarkData, forKey: "mappingFileBookmark")
        }
        UserDefaults.standard.set(url.path, forKey: PrefKey.mappingFilePath)
        filePathLabel.stringValue = url.lastPathComponent
        filePathLabel.toolTip = url.path

        guard let data = try? Data(contentsOf: url) else { return }

        if ext == "csv" {
            if let text = String(data: data, encoding: .utf8) {
                BSSIDMapping.shared.loadFromCSV(text)
            }
        } else {
            BSSIDMapping.shared.loadFromData(data)
        }

        NotificationCenter.default.post(name: Notification.Name("MappingSourceChanged"), object: nil)
    }

    @objc private func urlChanged(_ sender: NSTextField) {
        UserDefaults.standard.set(sender.stringValue, forKey: PrefKey.mappingURL)
        NotificationCenter.default.post(name: Notification.Name("MappingURLChanged"), object: nil)
    }

    @objc private func fetchIntervalChanged(_ sender: NSPopUpButton) {
        let value = selectedIntervalValue()
        UserDefaults.standard.set(value, forKey: PrefKey.fetchInterval)
        NotificationCenter.default.post(name: Notification.Name("MappingURLChanged"), object: nil)
    }

    @objc private func maxLengthChanged(_ sender: NSStepper) {
        let value = sender.integerValue
        maxLengthLabel.stringValue = "\(value)"
        UserDefaults.standard.set(value, forKey: PrefKey.apNameMaxLength)
        NotificationCenter.default.post(name: Notification.Name("DisplaySettingsChanged"), object: nil)
    }

    @objc private func showMappingEditor() {
        if mappingEditorController == nil {
            let controller = MappingEditorWindowController()
            controller.onChanged = { [weak self] in
                self?.updateManualCount()
                NotificationCenter.default.post(name: Notification.Name("MappingSourceChanged"), object: nil)
            }
            mappingEditorController = controller
        }
        mappingEditorController?.reload()
        mappingEditorController?.showWindow(nil)
        mappingEditorController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func addManualEntry(_ sender: NSButton) {
        let apName = manualApNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let bssid = manualBssidField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !apName.isEmpty, !bssid.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Missing Information"
            alert.informativeText = "Please enter both an AP name and a BSSID."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        guard bssid.contains(":") else {
            let alert = NSAlert()
            alert.messageText = "Invalid BSSID"
            alert.informativeText = "BSSID should be in the format XX:XX:XX:XX:XX:XX (e.g. 00:33:58:A9:B5:F0)."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        BSSIDMapping.shared.addManualEntry(apName: apName, bssid: bssid)

        manualApNameField.stringValue = ""
        manualBssidField.stringValue = ""
        updateManualCount()

        NotificationCenter.default.post(name: Notification.Name("MappingSourceChanged"), object: nil)
    }

    private func updateManualCount() {
        let count = BSSIDMapping.shared.manualEntries().count
        if count == 0 {
            manualCountLabel.stringValue = ""
        } else {
            manualCountLabel.stringValue = "\(count) manual entr\(count == 1 ? "y" : "ies") saved"
        }
    }

    @objc private func truncateAtColonChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: PrefKey.truncateAtColon)
        NotificationCenter.default.post(name: Notification.Name("DisplaySettingsChanged"), object: nil)
    }

    @objc private func geekModeChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: PrefKey.geekMode)
        NotificationCenter.default.post(name: Notification.Name("DisplaySettingsChanged"), object: nil)
    }

    @objc private func signalStyleChanged(_ sender: NSPopUpButton) {
        let value = (sender.titleOfSelectedItem?.hasPrefix("Lenient") == true) ? "lenient" : "standard"
        UserDefaults.standard.set(value, forKey: PrefKey.signalPercentStyle)
        NotificationCenter.default.post(name: Notification.Name("DisplaySettingsChanged"), object: nil)
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        let shouldEnable = sender.state == .on
        UserDefaults.standard.set(shouldEnable, forKey: PrefKey.launchAtLogin)

        if #available(macOS 13.0, *) {
            do {
                if shouldEnable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                sender.state = shouldEnable ? .off : .on
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    @objc private func notifyEnabledChanged(_ sender: NSButton) {
        let wantOn = sender.state == .on
        UserDefaults.standard.set(wantOn, forKey: PrefKey.notifyOnRoam)
        applyNotifyControlsEnabled(wantOn)

        if wantOn {
            // Request permission on every flip-to-on. macOS caches the result —
            // first call shows the prompt, subsequent calls return the cached answer.
            RoamNotifier.shared.requestPermission { [weak self] granted in
                guard let self = self else { return }
                if !granted {
                    // Roll the toggle back; surface why.
                    self.notifyCheckbox.state = .off
                    UserDefaults.standard.set(false, forKey: PrefKey.notifyOnRoam)
                    self.applyNotifyControlsEnabled(false)
                }
                self.refreshNotifyAuthStatus()
            }
        } else {
            refreshNotifyAuthStatus()
        }
    }

    @objc private func notifyModeChanged(_ sender: NSPopUpButton) {
        let value = (sender.titleOfSelectedItem == "All roams") ? "all" : "problemsOnly"
        UserDefaults.standard.set(value, forKey: PrefKey.notifyMode)
    }

    @objc private func sendTestNotification(_ sender: NSButton) {
        RoamNotifier.shared.sendTestNotification()
    }
}
