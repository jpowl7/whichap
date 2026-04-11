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

        Signal Quality
        ━━━━━━━━━━━━━━
        The menu bar text and Signal line turn red when your connection is Poor or Bad:

        • Excellent: better than -50 dBm
        • Good: -50 to -60 dBm
        • Fair: -60 to -70 dBm
        • Poor: -70 to -80 dBm (red)
        • Bad: worse than -80 dBm (red)

        Using the Dropdown
        ━━━━━━━━━━━━━━━━━━
        • Click any info item to copy its value to the clipboard
        • "Copy All to Clipboard" copies everything formatted for a support ticket
        • "Manufacturer" shows the AP vendor based on its BSSID (looked up from the IEEE database)
        • "Restart Wi-Fi" toggles your Wi-Fi off and back on
        • "Wi-Fi Settings" opens macOS Wi-Fi settings
        • "Mac Uptime" shows how long since your last restart
        • "Connection History" shows a log of every AP you've connected to

        Location Services
        ━━━━━━━━━━━━━━━━━
        WhichAP needs Location Services permission to read the BSSID — this is an Apple \
        requirement. Your location is never stored or transmitted.

        If you denied the permission, go to System Settings > Privacy & Security > \
        Location Services and enable it for WhichAP.
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
            "Location Services",
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
