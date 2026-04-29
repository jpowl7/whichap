import Cocoa

final class HelpWindowController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WhichAP Help"
        window.collectionBehavior = .moveToActiveSpace
        window.center()
        window.setFrameAutosaveName("HelpWindow")
        window.minSize = NSSize(width: 320, height: 300)

        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let helpText = """
        Getting Started
        ━━━━━━━━━━━━━━━
        WhichAP shows which Wi-Fi access point you're connected to. \
        Your SSID appears on the top line of the menu bar, and the AP name appears below it.

        To identify access points, you need to provide a mapping of BSSIDs (MAC addresses) to AP names.

        Providing Your BSSID Mapping
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Go to Preferences and choose a mapping source:

        • File — Import a .json or .csv file
        • URL — Point to a hosted mapping file that auto-refreshes
        • Manual Entry — Type in AP name and BSSID one at a time (the current BSSID auto-fills)

        Accepted file formats:
        • JSON with "apName" and "bssid" fields (Ruckus Data Studio exports supported)
        • CSV with apName,bssid columns

        Use "View & Edit Mappings" in Preferences to see all entries, search, and edit manual ones.

        Display Options
        ━━━━━━━━━━━━━━━
        In Preferences under Display:

        • AP Name Max Length — limits how many characters are shown in the menu bar
        • Truncate AP name at ":" — hides the technical suffix after ":" in AP names
        • Geek mode — changes the menu bar to show SSID:AP Name on the top line \
        and signal%, band, and channel on the bottom line (e.g. 84%|5GHz|ch149)
        • Signal % style — choose how RSSI maps to a percentage. Standard reads \
        conservatively (-65 dBm = 56%); Lenient reads friendlier (-65 dBm = 70%). \
        Underlying dBm and the Poor/Bad warning thresholds are unchanged.

        Signal Quality
        ━━━━━━━━━━━━━━
        The menu bar text and Signal line turn red when your connection is Poor or Bad:

        • Excellent: better than -50 dBm
        • Good: -50 to -60 dBm
        • Fair: -60 to -70 dBm
        • Poor: -70 to -80 dBm — red
        • Bad: worse than -80 dBm — red

        Using the Dropdown
        ━━━━━━━━━━━━━━━━━━
        • Click any info item to copy its value to the clipboard
        • "Copy All to Clipboard" copies everything formatted for a support ticket
        • "Manufacturer" shows the AP vendor based on its BSSID (looked up from the IEEE database)
        • "Restart Wi-Fi" toggles your Wi-Fi off and back on
        • "Wi-Fi Settings" opens macOS Wi-Fi settings
        • "Mac Uptime" shows how long since your last restart

        Connection History
        ━━━━━━━━━━━━━━━━━━
        Click "Connection History" in the dropdown to see every AP your Mac has been on \
        (up to 1000 entries, persisted across restarts). The window shows:

        • Time, AP Name, SSID, Band, Ch, Signal, BSSID — what you connected to
        • Type — what kind of event each row was:
          – Roam: mid-session AP switch (different BSSID, same SSID)
          – Channel: same AP, but it changed channel (often due to interference)
          – Reconnect: connected again after a brief disconnect
          – New SSID: connected to a different network
          – First: the first connection in the session
        • Left at — signal of the prior AP at the moment you roamed away (helps \
        spot APs you held too long)
        • Duration — how long you stayed on each AP
        • Flag (left column) — automatic problem detection:
          – Sticky (orange): held a weak AP (< -70 dBm) for over 30 minutes before roaming
          – Ping-pong (red): bounced between two APs within 60 seconds
          – Slow roam (yellow): brief disconnect during what should have been a seamless AP switch

        The filter popup at the top narrows the view to All, Roams only, or Problems only. \
        Refresh pulls in events that happened while the window was open.

        Notifications
        ━━━━━━━━━━━━━
        WhichAP can post a macOS notification each time you roam to a new AP. \
        Off by default. Enable in Preferences → Notifications:

        • Notify on roam events — toggles notifications on/off. The first time you \
        enable it, macOS will ask permission.
        • Notify for — choose between "All roams" (every AP change, including \
        when an AP changes channel on the same BSSID) or "Problems only" \
        (just sticky / ping-pong / slow-roam events).
        • Test Notification — fires a sample notification so you can confirm delivery works.

        Notification titles use the SSID name (e.g., "GCCstaffstuffz") so you can \
        tell at a glance which network the event happened on.

        If you've enabled notifications but aren't seeing banners, the Preferences \
        screen will show specific guidance — usually "Allow notifications" needs to \
        be on, or the alert style needs to be Banners or Alerts (not None) in \
        System Settings → Notifications → WhichAP.

        Location Services
        ━━━━━━━━━━━━━━━━━
        WhichAP needs Location Services permission to read the BSSID — this is an Apple \
        requirement. Your location is never stored or transmitted.

        If you denied the permission, go to System Settings > Privacy & Security > \
        Location Services and enable it for WhichAP.

        Troubleshooting
        ━━━━━━━━━━━━━━━
        "⚠ Location Off" in the menu bar:
        This means Location Services permission isn't granted for WhichAP. Open the \
        WhichAP menu — you'll see clear instructions and a button to open Location \
        Settings directly.

        "Location Services Disabled" in the menu:
        The system-wide Location Services switch is off. Open Location Settings (button \
        in the WhichAP menu) and turn on the master switch at the top of the list.

        "Location Access Required" in the menu:
        WhichAP is listed in Location Services but toggled off. Open Location Settings \
        and find WhichAP in the list — toggle it on.

        The permission prompt never appeared:
        On first launch, WhichAP shows an intro panel then triggers the macOS prompt. \
        If you missed it, click WhichAP in the menu bar, then click "Grant Location \
        Access…" to try again. If that doesn't work, open Location Settings and toggle \
        WhichAP on manually.

        For IT admins (Jamf / MDM):
        Location Services cannot be pre-granted via MDM configuration profiles — Apple \
        intentionally requires user consent. With WhichAP correctly signed (1.8.4+), \
        the macOS prompt fires reliably on first launch and the user clicks Allow once.
        """

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        // Style the text with section headers bold
        let attrString = NSMutableAttributedString(string: helpText, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ])

        let boldFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        let headers = [
            "Getting Started",
            "Providing Your BSSID Mapping",
            "Display Options",
            "Signal Quality",
            "Using the Dropdown",
            "Connection History",
            "Notifications",
            "Location Services",
            "Troubleshooting",
        ]
        for header in headers {
            let range = (helpText as NSString).range(of: header)
            if range.location != NSNotFound {
                attrString.addAttribute(.font, value: boldFont, range: range)
            }
        }

        textView.textStorage?.setAttributedString(attrString)

        scrollView.documentView = textView

        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
}
