import Cocoa

final class ConnectionHistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private enum Filter: Int {
        case all = 0
        case roamsOnly = 1
        case problemsOnly = 2
    }

    private enum EventType: String {
        case roam = "Roam"
        case reconnect = "Reconnect"
        case newSSID = "New SSID"
        case first = "First"
    }

    private enum ProblemFlag {
        case none
        case sticky      // long stay on weak signal then roamed
        case pingPong    // roamed back to a recent BSSID within 60s
        case slowRoam    // brief disconnect during what should've been a roam

        var label: String {
            switch self {
            case .none:     return ""
            case .sticky:   return "Sticky"
            case .pingPong: return "Ping-pong"
            case .slowRoam: return "Slow roam"
            }
        }

        var color: NSColor {
            switch self {
            case .none:     return .labelColor
            case .sticky:   return .systemOrange
            case .pingPong: return .systemRed
            case .slowRoam: return .systemYellow
            }
        }
    }

    private var tableView: NSTableView!
    private var filterPopup: NSPopUpButton!
    private var events: [ConnectionEvent] = []
    private var visibleIndices: [Int] = []
    private var currentFilter: Filter = .all

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 440),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Connection History"
        window.collectionBehavior = .moveToActiveSpace
        window.center()
        window.setFrameAutosaveName("ConnectionHistoryWindow")
        window.minSize = NSSize(width: 600, height: 240)

        self.init(window: window)
        setupUI()
    }

    func update(with events: [ConnectionEvent]) {
        self.events = events
        recomputeVisible()
        tableView?.reloadData()
        autoSizeColumns()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window else { return }

        let columns: [(id: String, title: String, width: CGFloat)] = [
            ("flag",     "",         70),
            ("time",     "Time",     130),
            ("type",     "Type",     80),
            ("ap",       "AP Name",  150),
            ("ssid",     "SSID",     90),
            ("band",     "Band",     50),
            ("channel",  "Ch",       50),
            ("rssi",     "Signal",   70),
            ("priorRssi","Left at",  70),
            ("duration", "Duration", 80),
            ("bssid",    "BSSID",    140),
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

        let filterLabel = NSTextField(labelWithString: "Show:")
        filterLabel.translatesAutoresizingMaskIntoConstraints = false

        filterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        filterPopup.addItems(withTitles: ["All", "Roams only", "Problems only"])
        filterPopup.target = self
        filterPopup.action = #selector(filterChanged)
        filterPopup.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshFromSource))
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        let clearButton = NSButton(title: "Clear History", target: self, action: #selector(clearHistory))
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = window.contentView else { return }
        contentView.addSubview(filterLabel)
        contentView.addSubview(filterPopup)
        contentView.addSubview(scrollView)
        contentView.addSubview(refreshButton)
        contentView.addSubview(clearButton)

        NSLayoutConstraint.activate([
            filterLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            filterLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),

            filterPopup.centerYAnchor.constraint(equalTo: filterLabel.centerYAnchor),
            filterPopup.leadingAnchor.constraint(equalTo: filterLabel.trailingAnchor, constant: 6),
            filterPopup.widthAnchor.constraint(equalToConstant: 160),

            scrollView.topAnchor.constraint(equalTo: filterPopup.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: clearButton.topAnchor, constant: -8),

            refreshButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            refreshButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            clearButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            clearButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Actions

    var onClear: (() -> Void)?
    var onRefresh: (() -> [ConnectionEvent])?

    @objc private func clearHistory() {
        events.removeAll()
        recomputeVisible()
        tableView.reloadData()
        autoSizeColumns()
        onClear?()
    }

    @objc private func refreshFromSource() {
        guard let fresh = onRefresh?() else { return }
        update(with: fresh)
    }

    @objc private func filterChanged() {
        currentFilter = Filter(rawValue: filterPopup.indexOfSelectedItem) ?? .all
        recomputeVisible()
        tableView.reloadData()
        autoSizeColumns()
    }

    // MARK: - Filtering

    private func recomputeVisible() {
        switch currentFilter {
        case .all:
            visibleIndices = Array(events.indices)
        case .roamsOnly:
            visibleIndices = events.indices.filter { eventType(at: $0) == .roam }
        case .problemsOnly:
            visibleIndices = events.indices.filter { problemFlag(at: $0) != .none }
        }
    }

    // MARK: - Derived fields

    /// Returns the immediately preceding (older) event, if any.
    /// events[] is newest-first, so the prior event is at index + 1.
    private func priorEvent(at index: Int) -> ConnectionEvent? {
        let prior = index + 1
        return prior < events.count ? events[prior] : nil
    }

    private func eventType(at index: Int) -> EventType {
        let event = events[index]
        guard let prior = priorEvent(at: index) else { return .first }
        if event.priorRSSI == nil { return .reconnect }
        if event.ssid != prior.ssid { return .newSSID }
        return .roam
    }

    /// Time spent on THIS row's AP — from when we connected until the next event
    /// replaced it. nil for events[0] (the current connection); use the menu's
    /// live "Connected: Xm" for that.
    private func durationOnAP(at index: Int) -> TimeInterval? {
        guard index > 0 else { return nil }
        return events[index - 1].timestamp.timeIntervalSince(events[index].timestamp)
    }

    /// Signal of THIS row's AP at the moment the client roamed away. Stored on the
    /// NEXT (newer) row's `priorRSSI`, which is when the capture happened. nil for
    /// the most recent row (still connected) or when we left via disconnect.
    private func leftAtRSSI(at index: Int) -> Int? {
        guard index > 0 else { return nil }
        return events[index - 1].priorRSSI
    }

    /// Gap between this event and the older event immediately before it.
    /// Used internally by problem-flag detection (semantically distinct from
    /// `durationOnAP`, which is about display).
    private func gapToPriorEvent(at index: Int) -> TimeInterval? {
        guard let prior = priorEvent(at: index) else { return nil }
        return events[index].timestamp.timeIntervalSince(prior.timestamp)
    }

    private func problemFlag(at index: Int) -> ProblemFlag {
        let type = eventType(at: index)

        // Sticky: this row's AP was held onto for a long time, with weak signal at
        // the moment we finally left. Flagged on the AP that was sticky (not the
        // roam-away event), so the row's other columns line up with the diagnosis.
        if index > 0,
           eventType(at: index - 1) == .roam,
           let dur = durationOnAP(at: index),
           dur > 30 * 60,
           let leftAt = leftAtRSSI(at: index),
           leftAt < -70 {
            return .sticky
        }

        // Slow roam: brief disconnect during what should have been a seamless roam.
        if type == .reconnect,
           let prior = priorEvent(at: index),
           prior.ssid == events[index].ssid,
           let gap = gapToPriorEvent(at: index),
           gap < 30 {
            return .slowRoam
        }

        // Ping-pong: roamed back to the same BSSID we were on two events ago, within 60s.
        if type == .roam,
           index + 2 < events.count {
            let twoBack = events[index + 2]
            if twoBack.bssid == events[index].bssid,
               events[index].timestamp.timeIntervalSince(twoBack.timestamp) < 60 {
                return .pingPong
            }
        }

        return .none
    }

    // MARK: - Formatters

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

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remMin = minutes % 60
        if hours < 24 { return remMin == 0 ? "\(hours)h" : "\(hours)h \(remMin)m" }
        let days = hours / 24
        let remHr = hours % 24
        return remHr == 0 ? "\(days)d" : "\(days)d \(remHr)h"
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return visibleIndices.count
    }

    // MARK: - NSTableViewDelegate

    private func cellText(columnId: String, eventIndex: Int) -> String {
        let event = events[eventIndex]
        switch columnId {
        case "flag":      return problemFlag(at: eventIndex).label
        case "time":      return formatTime(event.timestamp)
        case "type":      return eventType(at: eventIndex).rawValue
        case "ap":        return event.apName ?? "Unknown"
        case "ssid":      return event.ssid ?? "—"
        case "band":      return event.band
        case "channel":   return event.channel.map { "\($0)" } ?? "—"
        case "rssi":      return "\(event.rssi) dBm"
        case "priorRssi": return leftAtRSSI(at: eventIndex).map { "\($0) dBm" } ?? "—"
        case "duration":  return durationOnAP(at: eventIndex).map { formatDuration($0) } ?? "—"
        case "bssid":     return event.bssid ?? "—"
        default:          return ""
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let columnId = tableColumn?.identifier.rawValue,
              row < visibleIndices.count else { return nil }

        let eventIndex = visibleIndices[row]
        let text = cellText(columnId: columnId, eventIndex: eventIndex)
        let color: NSColor = (columnId == "flag") ? problemFlag(at: eventIndex).color : .labelColor

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
        cell.textColor = color
        return cell
    }

    /// Resize each column to fit its longest cell text (or its header, whichever
    /// is wider). Compares against the header font for the title and the cell
    /// font for the rows.
    private func autoSizeColumns() {
        guard let tableView = tableView else { return }
        let cellFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let headerFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        let cellAttrs: [NSAttributedString.Key: Any] = [.font: cellFont]
        let headerAttrs: [NSAttributedString.Key: Any] = [.font: headerFont]
        let cellPadding: CGFloat = 12  // NSTableView intercell + cell margins
        let headerPadding: CGFloat = 16  // accounts for sort indicator space

        for column in tableView.tableColumns {
            let columnId = column.identifier.rawValue
            var maxContent = (column.title as NSString).size(withAttributes: headerAttrs).width + headerPadding

            for visIndex in visibleIndices {
                let text = cellText(columnId: columnId, eventIndex: visIndex)
                let w = (text as NSString).size(withAttributes: cellAttrs).width + cellPadding
                if w > maxContent { maxContent = w }
            }

            column.width = max(column.minWidth, ceil(maxContent))
        }
    }
}
