import Cocoa

final class ConnectionHistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private var tableView: NSTableView!
    private var events: [ConnectionEvent] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Connection History"
        window.collectionBehavior = .moveToActiveSpace
        window.center()
        window.setFrameAutosaveName("ConnectionHistoryWindow")
        window.minSize = NSSize(width: 400, height: 200)

        self.init(window: window)
        setupUI()
    }

    func update(with events: [ConnectionEvent]) {
        self.events = events
        tableView?.reloadData()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window else { return }

        let columns: [(id: String, title: String, width: CGFloat)] = [
            ("time", "Time", 140),
            ("ap", "AP Name", 160),
            ("ssid", "SSID", 100),
            ("band", "Band", 60),
            ("rssi", "Signal", 70),
            ("bssid", "BSSID", 150),
        ]

        tableView = NSTableView()
        tableView.style = .fullWidth
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.dataSource = self
        tableView.delegate = self

        for col in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.id))
            column.title = col.title
            column.width = col.width
            column.minWidth = 40
            tableView.addTableColumn(column)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let clearButton = NSButton(title: "Clear History", target: self, action: #selector(clearHistory))
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = window.contentView else { return }
        contentView.addSubview(scrollView)
        contentView.addSubview(clearButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: clearButton.topAnchor, constant: -8),

            clearButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            clearButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Actions

    var onClear: (() -> Void)?

    @objc private func clearHistory() {
        events.removeAll()
        tableView.reloadData()
        onClear?()
    }

    // MARK: - Date Formatter

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm:ss a"
        return f
    }()

    private func formatTime(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        }
        return Self.dateTimeFormatter.string(from: date)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return events.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let columnId = tableColumn?.identifier.rawValue, row < events.count else { return nil }

        let event = events[row]
        let text: String

        switch columnId {
        case "time":
            text = formatTime(event.timestamp)
        case "ap":
            text = event.apName ?? "Unknown"
        case "ssid":
            text = event.ssid ?? "—"
        case "band":
            text = event.band
        case "rssi":
            text = "\(event.rssi) dBm"
        case "bssid":
            text = event.bssid ?? "—"
        default:
            text = ""
        }

        let cellId = NSUserInterfaceItemIdentifier("cell_\(columnId)")
        let cell: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField {
            cell = existing
        } else {
            cell = NSTextField(labelWithString: "")
            cell.identifier = cellId
            cell.lineBreakMode = .byTruncatingTail
            cell.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        }
        cell.stringValue = text
        return cell
    }
}
