import Cocoa
import CoreWLAN
import ServiceManagement

// MARK: - UserDefaults Keys

private enum PrefKey {
    static let mappingSource     = "mappingSource"
    static let mappingFilePath   = "mappingFilePath"
    static let mappingURL        = "mappingURL"
    static let fetchInterval     = "fetchInterval"
    static let apNameMaxLength   = "apNameMaxLength"
    static let showBand          = "showBand"
    static let launchAtLogin     = "launchAtLogin"
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
    // showBand removed — band is no longer shown in menu bar
    private var launchCheckbox:   NSButton!

    // Manual entry controls
    private var mappingEditorController: MappingEditorWindowController?
    private var manualApNameField:  NSTextField!
    private var manualBssidField:   NSTextField!
    private var addEntryButton:     NSButton!
    private var manualCountLabel:   NSTextField!
    private var manualApNameRow:    NSView!
    private var manualBssidRow:     NSView!
    private var manualButtonRow:    NSView!

    // Rows that toggle visibility
    private var fileRow:     NSView!
    private var urlRow:      NSView!
    private var intervalRow: NSView!
    private var formatHintRow: NSView!

    // Container that holds all rows — we recalculate its layout on source change
    private var contentView: NSView!

    // All rows in order (top to bottom visually)
    private var allRows: [NSView] = []

    // Section header marker
    private var sectionHeaders: Set<ObjectIdentifier> = []

    // MARK: Geometry constants

    private let windowWidth:  CGFloat = 420
    private let windowHeight: CGFloat = 500
    private let sideMargin:   CGFloat = 20
    private let rowHeight:    CGFloat = 26
    private let rowSpacing:   CGFloat = 8
    private let sectionGap:   CGFloat = 16
    private let labelWidth:   CGFloat = 130

    // MARK: Lifecycle

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WhichAP Preferences"
        window.isReleasedWhenClosed = false
        window.level = .floating

        self.init(window: window)

        buildUI()
        loadCurrentValues()
        updateConditionalVisibility(animated: false)
    }

    override func showWindow(_ sender: Any?) {
        // Pre-fill current BSSID if connected
        if let bssid = CWWiFiClient.shared().interface()?.bssid() {
            manualBssidField.stringValue = bssid.split(separator: ":")
                .map { octet -> String in
                    let hex = String(octet).uppercased()
                    return hex.count == 1 ? "0\(hex)" : hex
                }
                .joined(separator: ":")
        }
        updateManualCount()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let window = window else { return }

        let container = NSView(frame: window.contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        window.contentView = container
        contentView = container

        allRows = []

        // ── Section: Mapping Data ──────────────────────────────────

        allRows.append(makeSectionHeader("Mapping Data"))

        // Source row
        let sourceRow = makeRow()
        let sourceLabel = makeLabel("Source:")
        sourcePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        sourcePopUp.addItems(withTitles: ["Bundled", "File", "URL"])
        sourcePopUp.target = self
        sourcePopUp.action = #selector(mappingSourceChanged(_:))
        sourcePopUp.sizeToFit()
        sourceRow.addSubview(sourceLabel)
        sourceRow.addSubview(sourcePopUp)
        allRows.append(sourceRow)

        // File row (conditional)
        fileRow = makeRow()
        let fileLabel = makeLabel("File:")
        filePathLabel = NSTextField(labelWithString: "None selected")
        filePathLabel.lineBreakMode = .byTruncatingMiddle
        filePathLabel.textColor = .secondaryLabelColor
        chooseFileButton = NSButton(title: "Choose\u{2026}", target: self, action: #selector(chooseFile(_:)))
        chooseFileButton.bezelStyle = .rounded
        chooseFileButton.sizeToFit()
        fileRow.addSubview(fileLabel)
        fileRow.addSubview(filePathLabel)
        fileRow.addSubview(chooseFileButton)
        allRows.append(fileRow)

        // URL row (conditional)
        urlRow = makeRow()
        let urlLabel = makeLabel("URL:")
        urlField = NSTextField(frame: .zero)
        urlField.placeholderString = "https://example.com/mapping.json"
        urlField.target = self
        urlField.action = #selector(urlChanged(_:))
        urlRow.addSubview(urlLabel)
        urlRow.addSubview(urlField)
        allRows.append(urlRow)

        // Fetch Interval row (conditional)
        intervalRow = makeRow()
        let intervalLabel = makeLabel("Fetch Interval:")
        intervalPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        intervalPopUp.addItems(withTitles: ["Hourly", "Daily", "Weekly"])
        intervalPopUp.target = self
        intervalPopUp.action = #selector(fetchIntervalChanged(_:))
        intervalPopUp.sizeToFit()
        intervalRow.addSubview(intervalLabel)
        intervalRow.addSubview(intervalPopUp)
        allRows.append(intervalRow)

        // Format hint (conditional — shown for File and URL)
        formatHintRow = makeRow()
        let hintLabel = NSTextField(wrappingLabelWithString:
            "Accepted formats: JSON with \"apName\" and \"bssid\" fields, or CSV with apName,bssid columns. Ruckus Data Studio exports are supported.")
        hintLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.isSelectable = false
        formatHintRow.addSubview(hintLabel)
        allRows.append(formatHintRow)

        // ── Section: Manual Entry ────────────────────────────────────

        allRows.append(makeSectionHeader("Manual Entry"))

        // AP Name row
        manualApNameRow = makeRow()
        let apNameLabel = makeLabel("AP Name:")
        manualApNameField = NSTextField(frame: .zero)
        manualApNameField.placeholderString = "e.g. Lobby North"
        manualApNameRow.addSubview(apNameLabel)
        manualApNameRow.addSubview(manualApNameField)
        allRows.append(manualApNameRow)

        // BSSID row
        manualBssidRow = makeRow()
        let bssidLabel = makeLabel("BSSID:")
        manualBssidField = NSTextField(frame: .zero)
        manualBssidField.placeholderString = "e.g. 00:33:58:A9:B5:F0"
        manualBssidRow.addSubview(bssidLabel)
        manualBssidRow.addSubview(manualBssidField)
        allRows.append(manualBssidRow)

        // Add button + count row
        manualButtonRow = makeRow()
        addEntryButton = NSButton(title: "Add", target: self, action: #selector(addManualEntry(_:)))
        addEntryButton.bezelStyle = .rounded
        addEntryButton.sizeToFit()
        manualCountLabel = NSTextField(labelWithString: "")
        manualCountLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        manualCountLabel.textColor = .secondaryLabelColor
        manualButtonRow.addSubview(manualCountLabel)
        manualButtonRow.addSubview(addEntryButton)
        allRows.append(manualButtonRow)

        // View & Edit Mappings button row
        let editMappingsRow = makeRow()
        let editMappingsButton = NSButton(title: "View & Edit Mappings\u{2026}", target: self, action: #selector(showMappingEditor))
        editMappingsButton.bezelStyle = .rounded
        editMappingsButton.sizeToFit()
        editMappingsRow.addSubview(editMappingsButton)
        allRows.append(editMappingsRow)

        // ── Section: Display ───────────────────────────────────────

        allRows.append(makeSectionHeader("Display"))

        // AP Name Max Length row
        let maxLenRow = makeRow()
        let maxLenLabel = makeLabel("AP Name Max Length:")
        maxLengthLabel = NSTextField(labelWithString: "20")
        maxLengthLabel.alignment = .center
        maxLengthStepper = NSStepper(frame: .zero)
        maxLengthStepper.minValue = 5
        maxLengthStepper.maxValue = 50
        maxLengthStepper.increment = 1
        maxLengthStepper.valueWraps = false
        maxLengthStepper.target = self
        maxLengthStepper.action = #selector(maxLengthChanged(_:))
        maxLengthStepper.sizeToFit()
        maxLenRow.addSubview(maxLenLabel)
        maxLenRow.addSubview(maxLengthLabel)
        maxLenRow.addSubview(maxLengthStepper)
        allRows.append(maxLenRow)

        // ── Section: General ───────────────────────────────────────

        allRows.append(makeSectionHeader("General"))

        // Launch at Login row
        let launchRow = makeRow()
        launchCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(launchAtLoginChanged(_:)))
        launchRow.addSubview(launchCheckbox)
        allRows.append(launchRow)

        // Add all rows to container
        for row in allRows {
            container.addSubview(row)
        }

        layoutRows()
    }

    // MARK: - Layout

    private func layoutRows() {
        let usableWidth = windowWidth - sideMargin * 2
        var y = windowHeight - sideMargin

        for row in allRows {
            if row.isHidden { continue }

            let isSectionHeader = sectionHeaders.contains(ObjectIdentifier(row))
            if isSectionHeader {
                // Extra gap before section headers (but not before the very first one)
                if y < windowHeight - sideMargin {
                    y -= sectionGap
                }
                row.frame = NSRect(x: sideMargin, y: y - rowHeight, width: usableWidth, height: rowHeight)
                y -= rowHeight
                continue
            }

            let currentRowHeight: CGFloat
            if row === formatHintRow {
                // Wrapping hint label needs more height
                currentRowHeight = 48
                row.frame = NSRect(x: sideMargin, y: y - currentRowHeight, width: usableWidth, height: currentRowHeight)
                if let label = row.subviews.first as? NSTextField {
                    label.frame = NSRect(x: 0, y: 0, width: usableWidth, height: currentRowHeight)
                }
            } else {
                currentRowHeight = rowHeight
                row.frame = NSRect(x: sideMargin, y: y - currentRowHeight, width: usableWidth, height: currentRowHeight)
                layoutSubviewsOfRow(row, width: usableWidth)
            }
            y -= (currentRowHeight + rowSpacing)
        }
    }

    private func layoutSubviewsOfRow(_ row: NSView, width: CGFloat) {
        let h = rowHeight

        // Identify subviews by class to decide layout
        let subviews = row.subviews

        // Section header rows are just a single text field — already sized
        if sectionHeaders.contains(ObjectIdentifier(row)) { return }

        // Checkbox-only rows (Show Band, Launch at Login)
        if subviews.count == 1, let checkbox = subviews.first as? NSButton,
           checkbox.bezelStyle == .regularSquare || checkbox == launchCheckbox {
            checkbox.frame = NSRect(x: labelWidth + 4, y: 0, width: width - labelWidth - 4, height: h)
            return
        }

        // Single button row (View & Edit Mappings)
        if subviews.count == 1, let button = subviews.first as? NSButton, button.bezelStyle == .rounded {
            button.frame = NSRect(x: labelWidth + 4, y: 0, width: button.frame.width, height: h)
            return
        }

        // Stepper row (max length): label + value label + stepper
        if subviews.contains(where: { $0 is NSStepper }) {
            let label = subviews[0] as! NSTextField
            let valueLabel = subviews[1] as! NSTextField
            let stepper = subviews[2] as! NSStepper
            label.frame = NSRect(x: 0, y: 0, width: labelWidth, height: h)
            let stepperW: CGFloat = stepper.frame.width
            let valueLabelW: CGFloat = 36
            valueLabel.frame = NSRect(x: labelWidth + 4, y: 0, width: valueLabelW, height: h)
            stepper.frame = NSRect(x: labelWidth + 4 + valueLabelW + 4, y: 2, width: stepperW, height: h - 4)
            return
        }

        // File row: label + path label + choose button
        if subviews.contains(where: { $0 === chooseFileButton }) {
            let label = subviews[0] as! NSTextField
            let pathLabel = subviews[1] as! NSTextField
            let button = subviews[2] as! NSButton
            let btnW = button.frame.width
            label.frame = NSRect(x: 0, y: 0, width: labelWidth, height: h)
            button.frame = NSRect(x: width - btnW, y: 0, width: btnW, height: h)
            pathLabel.frame = NSRect(x: labelWidth + 4, y: 0, width: width - labelWidth - btnW - 12, height: h)
            return
        }

        // Manual entry button row: count label + add button
        if row === manualButtonRow {
            let btnW = addEntryButton.frame.width
            addEntryButton.frame = NSRect(x: labelWidth + 4, y: 0, width: btnW, height: h)
            manualCountLabel.frame = NSRect(x: labelWidth + btnW + 12, y: 0, width: width - labelWidth - btnW - 16, height: h)
            return
        }

        // PopUpButton row: label + popup
        if let popup = subviews.last as? NSPopUpButton {
            let label = subviews[0] as! NSTextField
            label.frame = NSRect(x: 0, y: 0, width: labelWidth, height: h)
            popup.frame = NSRect(x: labelWidth + 4, y: 0, width: width - labelWidth - 4, height: h)
            return
        }

        // Text field row (URL): label + text field
        if subviews.count == 2, subviews[1] is NSTextField, !(subviews[1] is NSSecureTextField) {
            let label = subviews[0] as! NSTextField
            let field = subviews[1] as! NSTextField
            label.frame = NSRect(x: 0, y: 0, width: labelWidth, height: h)
            field.frame = NSRect(x: labelWidth + 4, y: 0, width: width - labelWidth - 4, height: h)
            return
        }
    }

    // MARK: - Helpers: View creation

    private func makeRow() -> NSView {
        let row = NSView(frame: .zero)
        return row
    }

    private func makeSectionHeader(_ title: String) -> NSView {
        let row = NSView(frame: .zero)
        sectionHeaders.insert(ObjectIdentifier(row))

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 0, y: 2)
        row.addSubview(label)

        return row
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        return label
    }

    // MARK: - Load Stored Values

    private func loadCurrentValues() {
        let defaults = UserDefaults.standard

        // Register defaults
        defaults.register(defaults: [
            PrefKey.mappingSource:   "bundled",
            PrefKey.mappingURL:      "",
            PrefKey.fetchInterval:   "daily",
            PrefKey.apNameMaxLength: 20,
            PrefKey.showBand:        true,
            PrefKey.launchAtLogin:   true,
        ])

        // Mapping source
        let source = defaults.string(forKey: PrefKey.mappingSource) ?? "bundled"
        switch source {
        case "file": sourcePopUp.selectItem(withTitle: "File")
        case "url":  sourcePopUp.selectItem(withTitle: "URL")
        default:     sourcePopUp.selectItem(withTitle: "Bundled")
        }

        // File path
        if let path = defaults.string(forKey: PrefKey.mappingFilePath), !path.isEmpty {
            filePathLabel.stringValue = (path as NSString).lastPathComponent
            filePathLabel.toolTip = path
        }

        // URL
        urlField.stringValue = defaults.string(forKey: PrefKey.mappingURL) ?? ""

        // Fetch interval
        let interval = defaults.string(forKey: PrefKey.fetchInterval) ?? "daily"
        switch interval {
        case "hourly":  intervalPopUp.selectItem(withTitle: "Hourly")
        case "weekly":  intervalPopUp.selectItem(withTitle: "Weekly")
        default:        intervalPopUp.selectItem(withTitle: "Daily")
        }

        // Max length
        let maxLen = defaults.integer(forKey: PrefKey.apNameMaxLength)
        let clampedMaxLen = max(5, min(50, maxLen == 0 ? 20 : maxLen))
        maxLengthStepper.integerValue = clampedMaxLen
        maxLengthLabel.stringValue = "\(clampedMaxLen)"

        // Launch at login — read from SMAppService
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            launchCheckbox.state = (status == .enabled) ? .on : .off
        }

        // Manual entry count
        updateManualCount()
    }

    // MARK: - Conditional Visibility

    private func updateConditionalVisibility(animated: Bool) {
        let source = selectedSourceValue()

        fileRow.isHidden      = (source != "file")
        urlRow.isHidden       = (source != "url")
        intervalRow.isHidden  = (source != "url")
        formatHintRow.isHidden = (source == "bundled")

        layoutRows()
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
        let path = url.path
        let ext = url.pathExtension.lowercased()

        UserDefaults.standard.set(path, forKey: PrefKey.mappingFilePath)
        filePathLabel.stringValue = url.lastPathComponent
        filePathLabel.toolTip = path

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

        // Basic BSSID format validation (should contain colons)
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
                // Revert checkbox state on failure
                sender.state = shouldEnable ? .off : .on
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
}
