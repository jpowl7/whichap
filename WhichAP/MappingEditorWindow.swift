import Cocoa

final class MappingEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private var tableView: NSTableView!
    private var entries: [(apName: String, bssid: String, isManual: Bool)] = []
    private var removeButton: NSButton!
    private var countLabel: NSTextField?
    private var searchField: NSSearchField!
    private var filteredEntries: [(apName: String, bssid: String, isManual: Bool)] = []
    var onChanged: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BSSID Mappings"
        window.center()
        window.setFrameAutosaveName("MappingEditorWindow")
        window.minSize = NSSize(width: 400, height: 250)

        self.init(window: window)
        setupUI()
    }

    func reload() {
        entries = BSSIDMapping.shared.allEntries()
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField?.stringValue.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if query.isEmpty {
            filteredEntries = entries
        } else {
            filteredEntries = entries.filter {
                $0.apName.lowercased().contains(query) || $0.bssid.lowercased().contains(query)
            }
        }
        tableView?.reloadData()
        updateCount()
        updateRemoveButton()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window else { return }

        // Search field
        searchField = NSSearchField()
        searchField.placeholderString = "Filter by AP name or BSSID"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))

        tableView = NSTableView()
        tableView.style = .fullWidth
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.dataSource = self
        tableView.delegate = self

        let apColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("apName"))
        apColumn.title = "AP Name"
        apColumn.width = 200
        apColumn.minWidth = 80
        tableView.addTableColumn(apColumn)

        let bssidColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("bssid"))
        bssidColumn.title = "BSSID"
        bssidColumn.width = 180
        bssidColumn.minWidth = 80
        tableView.addTableColumn(bssidColumn)

        let sourceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        sourceColumn.title = "Source"
        sourceColumn.width = 70
        sourceColumn.minWidth = 50
        tableView.addTableColumn(sourceColumn)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        removeButton = NSButton(title: "Remove Selected", target: self, action: #selector(removeSelected))
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.isEnabled = false

        let countLabel = NSTextField(labelWithString: "")
        countLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        self.countLabel = countLabel

        guard let contentView = window.contentView else { return }
        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)
        contentView.addSubview(removeButton)
        contentView.addSubview(countLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: removeButton.topAnchor, constant: -8),

            removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            removeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            countLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: removeButton.centerYAnchor),
        ])

        // Listen for selection changes to enable/disable remove button
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tableSelectionChanged),
            name: NSTableView.selectionDidChangeNotification,
            object: tableView
        )
    }

    private func updateCount() {
        let manualCount = entries.filter { $0.isManual }.count
        let totalCount = entries.count
        countLabel?.stringValue = "\(totalCount) mappings (\(manualCount) manual)"
    }

    private func updateRemoveButton() {
        let row = tableView.selectedRow
        if row >= 0, row < filteredEntries.count, filteredEntries[row].isManual {
            removeButton.isEnabled = true
        } else {
            removeButton.isEnabled = false
        }
    }

    // MARK: - Actions

    @objc private func searchChanged(_ sender: NSSearchField) {
        applyFilter()
    }

    @objc private func tableSelectionChanged(_ notification: Notification) {
        updateRemoveButton()
    }

    @objc private func removeSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredEntries.count, filteredEntries[row].isManual else { return }
        let bssid = filteredEntries[row].bssid
        BSSIDMapping.shared.removeManualEntry(bssid: bssid)
        reload()
        onChanged?()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredEntries.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let columnId = tableColumn?.identifier.rawValue, row < filteredEntries.count else { return nil }

        let entry = filteredEntries[row]
        let text: String
        switch columnId {
        case "apName": text = entry.apName
        case "bssid":  text = entry.bssid
        case "source": text = entry.isManual ? "Manual" : "Bundled"
        default:       text = ""
        }

        let isEditable = entry.isManual && columnId != "source"

        let cellId = NSUserInterfaceItemIdentifier("mapping_\(columnId)")
        let cell: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField {
            cell = existing
        } else {
            cell = NSTextField(string: "")
            cell.identifier = cellId
            cell.isBordered = false
            cell.drawsBackground = false
            cell.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            cell.lineBreakMode = .byTruncatingTail
        }
        cell.stringValue = text
        cell.isEditable = isEditable
        cell.textColor = entry.isManual ? .controlTextColor : .secondaryLabelColor

        if isEditable {
            cell.target = self
            cell.action = #selector(cellEdited(_:))
        } else {
            cell.target = nil
            cell.action = nil
        }

        return cell
    }

    @objc private func cellEdited(_ sender: NSTextField) {
        let row = tableView.row(for: sender)
        let col = tableView.column(for: sender)
        guard row >= 0, row < filteredEntries.count, col >= 0 else { return }
        guard filteredEntries[row].isManual else { return }

        let columnId = tableView.tableColumns[col].identifier.rawValue
        let oldEntry = filteredEntries[row]
        let newValue = sender.stringValue.trimmingCharacters(in: .whitespaces)

        BSSIDMapping.shared.removeManualEntry(bssid: oldEntry.bssid)

        let newApName = columnId == "apName" ? newValue : oldEntry.apName
        let newBssid = columnId == "bssid" ? newValue : oldEntry.bssid

        if !newApName.isEmpty, !newBssid.isEmpty {
            BSSIDMapping.shared.addManualEntry(apName: newApName, bssid: newBssid)
        }

        reload()
        onChanged?()
    }
}
