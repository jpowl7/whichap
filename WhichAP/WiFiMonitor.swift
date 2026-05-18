import Foundation
import CoreWLAN
import CoreLocation
import UserNotifications
import Network
import AppKit

// MARK: - LocationAccess

enum LocationAccess: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case systemDisabled
}

// MARK: - InternetReachability

enum InternetReachability: Equatable {
    case unknown        // initial state, before first probe completes (or feature off)
    case reachable      // path satisfied AND probe returned Success body
    case captive        // probe returned non-Success body (captive portal intercept)
    case unreachable    // path .unsatisfied OR probe failed N times consecutively
}

// MARK: - WiFiConnectionInfo

struct WiFiConnectionInfo {
    let ssid: String?
    let bssid: String?
    let rssi: Int
    let noise: Int
    let channelNumber: Int
    let channelWidth: String
    let band: String
    let transmitRate: Double
    let locationAuthorized: Bool
    let phyMode: String
    let security: String
    let ipAddress: String?

    /// Signal-to-noise ratio as a positive value.
    var snr: Int {
        return rssi - noise
    }

    /// Signal strength as a percentage (0–100). Two formulas selectable via
    /// the `signalPercentStyle` user default:
    ///   - "standard" (default): clamps to -100..-37, then scales. Reads
    ///      conservatively (-65 dBm = 56%).
    ///   - "lenient": original linear mapping `(rssi+100)*2` clamped 0..100.
    ///      Reads friendlier (-65 dBm = 70%).
    var signalPercent: Int {
        let style = UserDefaults.standard.string(forKey: "signalPercentStyle") ?? "standard"
        if style == "lenient" {
            return max(0, min(100, 2 * (100 + rssi)))
        }
        let clamped = max(-100, min(-37, rssi))
        return (clamped + 100) * 100 / 63
    }

    /// Noise floor as a percentage (0–100), where lower is better.
    var noisePercent: Int {
        // Noise is typically -80 to -100 dBm; map to 0-100 where 0% = -100, 100% = 0
        return max(0, min(100, 100 + noise))
    }

    /// Human-readable signal quality derived from RSSI.
    let signalQuality: SignalQuality

    /// Current internet-reachability state (event-driven, opt-in via the
    /// `checkInternet` UserDefault). `.unknown` when the feature is off or
    /// before the first probe has completed.
    let internetReachability: InternetReachability

    /// Public-facing (egress) IPv4 address as reported by api.ipify.org.
    /// Fetched once after each successful captive-probe verdict; nil when
    /// the feature is off, when the verdict is not `.reachable`, or before
    /// the first ipify response arrives.
    let externalIPAddress: String?
}

// MARK: - SignalQuality

enum SignalQuality: String {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case bad = "Bad"

    init(rssi: Int) {
        switch rssi {
        case let r where r > -50:
            self = .excellent
        case -60 ... -50:
            self = .good
        case -70 ... -61:
            self = .fair
        case -80 ... -71:
            self = .poor
        default:
            self = .bad
        }
    }
}

// MARK: - ConnectionEvent

struct ConnectionEvent: Codable {
    let timestamp: Date
    let ssid: String?
    let bssid: String?
    let apName: String?
    let rssi: Int
    let band: String
    /// Signal of the prior AP at the moment the client roamed away.
    /// nil for first-ever connection, post-disconnect reconnects, and pre-1.9.0 entries.
    let priorRSSI: Int?
    /// Channel the AP was on at the moment of the event. nil for entries
    /// recorded before channel was tracked (pre-1.9.0).
    let channel: Int?

    init(timestamp: Date, ssid: String?, bssid: String?, apName: String?, rssi: Int, band: String, priorRSSI: Int? = nil, channel: Int? = nil) {
        self.timestamp = timestamp
        self.ssid = ssid
        self.bssid = bssid
        self.apName = apName
        self.rssi = rssi
        self.band = band
        self.priorRSSI = priorRSSI
        self.channel = channel
    }
}

// MARK: - ConnectionHistoryStore

final class ConnectionHistoryStore {
    static let shared = ConnectionHistoryStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("WhichAP", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("connection-history.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [ConnectionEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let events = try? decoder.decode([ConnectionEvent].self, from: data) else {
            return []
        }
        return events
    }

    func save(_ events: [ConnectionEvent]) {
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - WiFiMonitorDelegate

protocol WiFiMonitorDelegate: AnyObject {
    func wifiMonitor(_ monitor: WiFiMonitor, didUpdateConnection info: WiFiConnectionInfo?)
    func wifiMonitor(_ monitor: WiFiMonitor, didChangeLocationAccess access: LocationAccess)
}

// MARK: - WiFiMonitor

final class WiFiMonitor: NSObject, CLLocationManagerDelegate, CWEventDelegate, ReachabilityMonitorDelegate {

    // MARK: Polling intervals

    private enum PollInterval {
        static let stable: TimeInterval = 10.0
        static let roaming: TimeInterval = 2.0
        static let disconnected: TimeInterval = 5.0
        static let roamingSettleTime: TimeInterval = 30.0
    }

    // MARK: Polling state

    private enum PollState {
        case stable
        case roaming
        case disconnected
    }

    // MARK: Properties

    weak var delegate: WiFiMonitorDelegate?

    private let locationManager = CLLocationManager()
    private var pollTimer: Timer?
    private var pollState: PollState = .disconnected

    private var lastBSSID: String?
    private var lastRSSI: Int?
    private var lastChannel: Int?
    private var bssidStableSince: Date?

    /// First event after app launch is always a "fake roam" — fresh process
    /// state means lastBSSID is nil so the first poll records a reconnect-type
    /// event even when the user hasn't actually moved. Suppress the notification
    /// for that first event only.
    private var hasNotifiedSinceLaunch = false

    /// Optional reachability monitor — only running when the `checkInternet`
    /// pref is on. When off, `current` stays `.unknown` and the UI ignores it.
    private let reachabilityMonitor = ReachabilityMonitor()
    var internetReachability: InternetReachability { reachabilityMonitor.current }

    /// When the current AP connection started (BSSID first seen or changed)
    private(set) var connectedToAPSince: Date?

    /// History of AP connections, newest first
    private(set) var connectionHistory: [ConnectionEvent] = []

    private(set) var locationAccess: LocationAccess = .notDetermined
    private(set) var latestInfo: WiFiConnectionInfo?

    var locationAuthorized: Bool { locationAccess == .authorized }

    // MARK: Lifecycle

    private let wifiClient = CWWiFiClient.shared()

    override init() {
        super.init()
        connectionHistory = ConnectionHistoryStore.shared.load()
        locationManager.delegate = self
        // On macOS, setting the delegate does not reliably fire the initial
        // authorization callback, so read the current status directly.
        locationAccess = Self.resolveAccess(locationManager.authorizationStatus)

        // Monitor Wi-Fi events so we detect reconnects after toggles
        wifiClient.delegate = self
        try? wifiClient.startMonitoringEvent(with: .ssidDidChange)
        try? wifiClient.startMonitoringEvent(with: .linkDidChange)
        try? wifiClient.startMonitoringEvent(with: .powerDidChange)

        reachabilityMonitor.delegate = self
        applyReachabilityPref()

        // React to user toggling the pref in Preferences.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkInternetSettingChanged),
            name: Notification.Name("InternetCheckSettingChanged"),
            object: nil
        )

        startPolling(interval: PollInterval.disconnected)
    }

    /// Called when the user flips the "Flag missing internet access" toggle.
    @objc private func checkInternetSettingChanged() {
        applyReachabilityPref()
        // Force a refresh so menu bar reflects the new state immediately.
        DispatchQueue.main.async { [weak self] in self?.poll() }
    }

    private func applyReachabilityPref() {
        if UserDefaults.standard.bool(forKey: "checkInternet") {
            reachabilityMonitor.start()
        } else {
            reachabilityMonitor.stop()
        }
    }

    private static func resolveAccess(_ status: CLAuthorizationStatus) -> LocationAccess {
        if !CLLocationManager.locationServicesEnabled() {
            return .systemDisabled
        }
        switch status {
        case .notDetermined:                return .notDetermined
        case .authorized, .authorizedAlways: return .authorized
        case .denied:                        return .denied
        case .restricted:                    return .restricted
        @unknown default:                    return .denied
        }
    }

    deinit {
        stopPolling()
    }

    // MARK: Location permission

    /// Triggers the macOS location permission prompt if status is .notDetermined.
    /// Caller should activate the app first so the prompt appears on top.
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
        // Belt-and-suspenders: on some macOS versions, LSUIElement apps need
        // startUpdatingLocation() to actually surface the prompt. We stop
        // updating as soon as we get a determinate authorization status.
        locationManager.startUpdatingLocation()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let newAccess = Self.resolveAccess(status)

        if status != .notDetermined {
            manager.stopUpdatingLocation()
        }

        let changed = newAccess != locationAccess
        locationAccess = newAccess
        if changed {
            delegate?.wifiMonitor(self, didChangeLocationAccess: newAccess)
        }
        poll()
    }

    // MARK: CWEventDelegate

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in
            self?.poll()
        }
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in
            self?.poll()
        }
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in
            self?.poll()
        }
    }

    // MARK: Polling

    private func startPolling(interval: TimeInterval) {
        stopPolling()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func clearHistory() {
        connectionHistory.removeAll()
        ConnectionHistoryStore.shared.save(connectionHistory)
    }

    private func recordConnectionEvent(for info: WiFiConnectionInfo, priorRSSI: Int?) {
        let fullName = info.bssid.flatMap { BSSIDMapping.shared.apName(forBSSID: $0) }
        let apName = fullName.map { Self.displayName(from: $0) }
        let event = ConnectionEvent(
            timestamp: Date(),
            ssid: info.ssid,
            bssid: info.bssid,
            apName: apName,
            rssi: info.rssi,
            band: info.band,
            priorRSSI: priorRSSI,
            channel: info.channelNumber
        )
        connectionHistory.insert(event, at: 0)
        if connectionHistory.count > 1000 {
            connectionHistory.removeSubrange(1000...)
        }
        ConnectionHistoryStore.shared.save(connectionHistory)

        if hasNotifiedSinceLaunch {
            RoamNotifier.shared.notifyIfNeeded(events: connectionHistory)
        } else {
            hasNotifiedSinceLaunch = true
        }
    }

    func poll() {
        let info = readWiFiInfo()
        latestInfo = info

        updatePollState(for: info)
        delegate?.wifiMonitor(self, didUpdateConnection: info)
    }

    // MARK: Adaptive polling state machine

    private func updatePollState(for info: WiFiConnectionInfo?) {
        guard let info = info, info.bssid != nil else {
            // Disconnected
            if pollState != .disconnected {
                pollState = .disconnected
                lastBSSID = nil
                lastRSSI = nil
                lastChannel = nil
                bssidStableSince = nil
                connectedToAPSince = nil
                startPolling(interval: PollInterval.disconnected)
            }
            return
        }

        let currentBSSID = info.bssid

        if currentBSSID != lastBSSID {
            // BSSID changed — record history event and enter roaming state.
            // priorRSSI captures the OLD AP's last-known signal (the "how bad
            // did it get before we roamed" number); nil if we came from disconnected.
            let now = Date()
            let priorRSSI = (lastBSSID != nil) ? lastRSSI : nil
            recordConnectionEvent(for: info, priorRSSI: priorRSSI)

            lastBSSID = currentBSSID
            lastRSSI = info.rssi
            lastChannel = info.channelNumber
            bssidStableSince = now
            connectedToAPSince = now
            if pollState != .roaming {
                pollState = .roaming
                startPolling(interval: PollInterval.roaming)
            }
            // New AP — re-probe internet reachability (no-op if pref is off).
            reachabilityMonitor.networkAssociationChanged()
        } else if pollState == .disconnected {
            // Transitioned from disconnected to connected
            let now = Date()
            recordConnectionEvent(for: info, priorRSSI: nil)

            lastBSSID = currentBSSID
            lastRSSI = info.rssi
            lastChannel = info.channelNumber
            bssidStableSince = now
            connectedToAPSince = now
            pollState = .stable
            startPolling(interval: PollInterval.stable)
            // Re-associated after a disconnect — re-probe (no-op if pref is off).
            reachabilityMonitor.networkAssociationChanged()
        } else {
            // Same BSSID — but the AP may have changed channel (interference,
            // RRM, ChannelFly, etc.). Record a separate event when that happens.
            // Detected as a non-roam by ConnectionAnalysis (same BSSID as prior).
            if let prevCh = lastChannel,
               info.channelNumber != 0,
               info.channelNumber != prevCh {
                recordConnectionEvent(for: info, priorRSSI: lastRSSI)
            }
            lastRSSI = info.rssi
            lastChannel = info.channelNumber

            if pollState == .roaming,
               let stableSince = bssidStableSince,
               Date().timeIntervalSince(stableSince) >= PollInterval.roamingSettleTime {
                pollState = .stable
                startPolling(interval: PollInterval.stable)
            }
        }
    }

    // MARK: CoreWLAN reading

    private func readWiFiInfo() -> WiFiConnectionInfo? {
        guard let interface = CWWiFiClient.shared().interface() else {
            return nil
        }

        // If there is no SSID the interface is likely disconnected.
        let ssid = interface.ssid()
        guard ssid != nil else {
            return nil
        }
        let rawBSSID = interface.bssid()
        let bssid = rawBSSID.map { normalizeBSSID($0) }
        let rssi = interface.rssiValue()
        let noise = interface.noiseMeasurement()
        let txRate = interface.transmitRate()

        let channel = interface.wlanChannel()
        let channelNumber = channel?.channelNumber ?? 0
        let channelWidth = channel.map { humanReadableWidth($0.channelWidth) } ?? "Unknown"
        let band = channel.map { humanReadableBand($0.channelBand) } ?? "?"
        let phyMode = humanReadablePHYMode(interface.activePHYMode())
        let security = humanReadableSecurity(interface.security())
        let ipAddress = Self.getWiFiIPAddress()

        return WiFiConnectionInfo(
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            noise: noise,
            channelNumber: channelNumber,
            channelWidth: channelWidth,
            band: band,
            transmitRate: txRate,
            locationAuthorized: locationAccess == .authorized,
            phyMode: phyMode,
            security: security,
            ipAddress: ipAddress,
            signalQuality: SignalQuality(rssi: rssi),
            internetReachability: reachabilityMonitor.current,
            externalIPAddress: reachabilityMonitor.externalIP
        )
    }

    // MARK: ReachabilityMonitorDelegate (forwarded as a regular update)

    /// Reachability state changes don't carry new Wi-Fi info, but the menu bar
    /// needs to repaint (red on captive/unreachable, normal on reachable).
    /// Re-poll so the freshly-built `WiFiConnectionInfo` carries the new
    /// `internetReachability` value through the existing delegate path.
    func reachabilityDidChange(_ reachability: InternetReachability) {
        poll()
    }

    // MARK: AP display name

    /// Returns only the friendly location portion of an AP name (before " : ")
    /// when the user has enabled truncation in preferences.
    static func displayName(from fullName: String) -> String {
        guard UserDefaults.standard.bool(forKey: "truncateAtColon") else { return fullName }
        if let range = fullName.range(of: " : ") {
            return fullName[fullName.startIndex..<range.lowerBound]
                .trimmingCharacters(in: .whitespaces)
        }
        return fullName
    }

    // MARK: BSSID normalization

    /// Converts a raw BSSID string to uppercase, zero-padded octets.
    /// e.g. "0:33:58:a9:b5:f0" → "00:33:58:A9:B5:F0"
    private func normalizeBSSID(_ bssid: String) -> String {
        return bssid
            .split(separator: ":")
            .map { octet -> String in
                let hex = String(octet).uppercased()
                return hex.count == 1 ? "0\(hex)" : hex
            }
            .joined(separator: ":")
    }

    // MARK: Band detection

    private func humanReadableBand(_ band: CWChannelBand) -> String {
        switch band {
        case .band2GHz:
            return "2.4 GHz"
        case .band5GHz:
            return "5 GHz"
        case .band6GHz:
            return "6 GHz"
        case .bandUnknown:
            return "?"
        @unknown default:
            return "?"
        }
    }

    // MARK: Channel width

    private func humanReadableWidth(_ width: CWChannelWidth) -> String {
        switch width {
        case .width20MHz:
            return "20 MHz"
        case .width40MHz:
            return "40 MHz"
        case .width80MHz:
            return "80 MHz"
        case .width160MHz:
            return "160 MHz"
        case .widthUnknown:
            return "Unknown"
        @unknown default:
            return "\(width.rawValue) MHz"
        }
    }

    // MARK: PHY mode

    private func humanReadablePHYMode(_ mode: CWPHYMode) -> String {
        switch mode {
        case .mode11a:   return "802.11a"
        case .mode11b:   return "802.11b"
        case .mode11g:   return "802.11g"
        case .mode11n:   return "802.11n (Wi-Fi 4)"
        case .mode11ac:  return "802.11ac (Wi-Fi 5)"
        case .mode11ax:  return "802.11ax (Wi-Fi 6)"
        case .modeNone:  return "None"
        @unknown default: return "Unknown"
        }
    }

    // MARK: Security

    private func humanReadableSecurity(_ security: CWSecurity) -> String {
        switch security {
        case .wpa3Personal:      return "WPA3 Personal"
        case .wpa3Enterprise:    return "WPA3 Enterprise"
        case .wpa3Transition:    return "WPA3/WPA2"
        case .wpa2Personal:      return "WPA2 Personal"
        case .wpa2Enterprise:    return "WPA2 Enterprise"
        case .wpaPersonal:       return "WPA Personal"
        case .wpaPersonalMixed:  return "WPA/WPA2 Personal"
        case .wpaEnterprise:     return "WPA Enterprise"
        case .wpaEnterpriseMixed: return "WPA/WPA2 Enterprise"
        case .dynamicWEP:        return "Dynamic WEP"
        case .none:              return "Open"
        case .OWE:               return "OWE"
        case .oweTransition:     return "OWE Transition"
        case .unknown:           return "Unknown"
        @unknown default:        return "Unknown"
        }
    }

    // MARK: IP address

    /// Returns the IPv4 address of the Wi-Fi interface (en0).
    static func getWiFiIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0 else { continue }

            let family = current.pointee.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }  // IPv4 only

            guard let name = current.pointee.ifa_name,
                  String(cString: name) == "en0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                current.pointee.ifa_addr,
                socklen_t(current.pointee.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            )
            if result == 0 {
                return String(cString: hostname)
            }
        }
        return nil
    }
}

// MARK: - ConnectionAnalysis
//
// Shared, pure helpers used by both `ConnectionHistoryWindow` (to render rows)
// and `RoamNotifier` (to decide whether to fire a notification on a fresh roam).
// Operates on the newest-first `[ConnectionEvent]` array — same convention
// the rest of the app uses.

struct ConnectionAnalysis {

    enum EventType: String {
        case roam = "Roam"
        case reconnect = "Reconnect"
        case newSSID = "New SSID"
        case first = "First"
        case channelChange = "Channel"
    }

    enum ProblemFlag {
        case none, sticky, pingPong, slowRoam
    }

    static func eventType(in events: [ConnectionEvent], at index: Int) -> EventType {
        guard index + 1 < events.count else { return .first }
        let event = events[index]
        let prior = events[index + 1]
        // Same BSSID as the prior event = the AP didn't change, only its channel did.
        if event.bssid == prior.bssid, event.bssid != nil { return .channelChange }
        if event.priorRSSI == nil { return .reconnect }
        if event.ssid != prior.ssid { return .newSSID }
        return .roam
    }

    /// Time spent on THIS index's AP — from when we connected until the next
    /// event replaced it. nil for events[0] (still connected) and for the
    /// oldest event (no successor known).
    static func durationOnAP(in events: [ConnectionEvent], at index: Int) -> TimeInterval? {
        guard index > 0 else { return nil }
        return events[index - 1].timestamp.timeIntervalSince(events[index].timestamp)
    }

    /// Signal of THIS index's AP at the moment of leaving. Captured on the
    /// next-newer event's `priorRSSI`.
    static func leftAtRSSI(in events: [ConnectionEvent], at index: Int) -> Int? {
        guard index > 0 else { return nil }
        return events[index - 1].priorRSSI
    }

    static func problemFlag(in events: [ConnectionEvent], at index: Int) -> ProblemFlag {
        let type = eventType(in: events, at: index)

        // Sticky: this row's AP was held a long time, weak signal at leaving.
        if index > 0,
           eventType(in: events, at: index - 1) == .roam,
           let dur = durationOnAP(in: events, at: index),
           dur > 30 * 60,
           let leftAt = leftAtRSSI(in: events, at: index),
           leftAt < -70 {
            return .sticky
        }

        // Slow roam: brief disconnect during what should have been a seamless roam.
        if type == .reconnect,
           index + 1 < events.count,
           events[index + 1].ssid == events[index].ssid {
            let gap = events[index].timestamp.timeIntervalSince(events[index + 1].timestamp)
            if gap < 30 { return .slowRoam }
        }

        // Ping-pong: roamed back to the BSSID we were on two events ago, within 60s.
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
}

// MARK: - RoamNotifier
//
// Posts macOS user notifications on roam events. Disabled by default; user
// flips it on in Preferences, which calls `requestAuthorization()` once. If
// permission is denied the toggle is force-rolled-back by the caller.
//
// Notification mode is read live from UserDefaults each call (cheap, no caching).

final class RoamNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RoamNotifier()
    private override init() {
        super.init()
        // Become the delegate so we can opt into foreground banner display —
        // macOS suppresses banners for the foreground app by default.
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    enum NotifyMode: String {
        case all
        case problemsOnly
    }

    enum PrefKey {
        static let enabled = "notifyOnRoam"
        static let mode = "notifyMode"
    }

    /// Ask macOS for notification permission. Completion fires on main thread
    /// with the granted flag. Safe to call repeatedly; the system caches the
    /// answer after the first prompt.
    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Check current authorization status (no prompt). Useful before sending.
    func currentAuthorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    /// Called from `WiFiMonitor.recordConnectionEvent` after the new event has
    /// been inserted at `events[0]`. Decides whether to post based on user pref
    /// and the current event's analysis.
    func notifyIfNeeded(events: [ConnectionEvent]) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: PrefKey.enabled) else { return }
        guard !events.isEmpty else { return }

        let modeStr = defaults.string(forKey: PrefKey.mode) ?? NotifyMode.problemsOnly.rawValue
        let mode = NotifyMode(rawValue: modeStr) ?? .problemsOnly

        // Check fresh roam at index 0 AND the AP we just left at index 1, since
        // sticky flags the AP that was held (events[1]), not the new one.
        let flag0 = ConnectionAnalysis.problemFlag(in: events, at: 0)
        let flag1 = events.count > 1 ? ConnectionAnalysis.problemFlag(in: events, at: 1) : .none

        switch mode {
        case .all:
            // Skip the very first event of a session (no actionable info).
            let type0 = ConnectionAnalysis.eventType(in: events, at: 0)
            guard type0 != .first else { return }
            postNotification(title: titleForEvent(events: events), body: bodyForRoam(events: events))
        case .problemsOnly:
            if flag0 != .none {
                postNotification(title: titleForEvent(events: events), body: bodyForFlag(flag0, events: events, at: 0))
            } else if flag1 != .none {
                postNotification(title: titleForEvent(events: events), body: bodyForFlag(flag1, events: events, at: 1))
            }
        }
    }

    /// Fire a fake notification for the user to verify delivery works.
    func sendTestNotification() {
        postNotification(title: "WhichAP", body: "Test notification — if you see this, WhichAP can deliver roam alerts.")
    }

    /// Notification title is the SSID of the new connection so a glance at the
    /// banner tells you which network the event happened on. Falls back to
    /// "WhichAP" when SSID isn't known.
    private func titleForEvent(events: [ConnectionEvent]) -> String {
        events.first?.ssid ?? "WhichAP"
    }

    // MARK: Body formatting

    private func bodyForRoam(events: [ConnectionEvent]) -> String {
        let now = events[0]
        let newAP = now.apName ?? now.bssid ?? "Unknown AP"
        let type = ConnectionAnalysis.eventType(in: events, at: 0)

        switch type {
        case .channelChange where events.count > 1:
            let prevCh = events[1].channel.map { "\($0)" } ?? "?"
            let nowCh = now.channel.map { "\($0)" } ?? "?"
            return "\(newAP) changed channel: \(prevCh) → \(nowCh)"

        case .newSSID:
            // Different network entirely — SSID title already shows the new
            // network, so "from Y" would be misleading.
            return "Connected to \(newAP)"

        case .reconnect:
            // Came through a disconnect; we don't really know if "from X"
            // is meaningful here (could've slept and moved buildings).
            return "Reconnected to \(newAP)"

        case .roam where events.count > 1:
            let prevAP = events[1].apName ?? events[1].bssid ?? "Unknown"
            return "Roamed to \(newAP) from \(prevAP)"

        default:
            return "Connected to \(newAP)"
        }
    }

    private func bodyForFlag(_ flag: ProblemFlagAlias, events: [ConnectionEvent], at index: Int) -> String {
        switch flag {
        case .sticky:
            let stickyAP = events[index].apName ?? events[index].bssid ?? "Unknown"
            let nextAP = events[index - 1].apName ?? events[index - 1].bssid ?? "Unknown"
            let dur = ConnectionAnalysis.durationOnAP(in: events, at: index).map { formatDuration($0) } ?? "?"
            return "Sticky roam — held \(stickyAP) for \(dur) before switching to \(nextAP)"

        case .pingPong:
            let now = events[index].apName ?? events[index].bssid ?? "Unknown"
            let mid = events[index + 1].apName ?? events[index + 1].bssid ?? "Unknown"
            let prior = events[index + 2].apName ?? events[index + 2].bssid ?? "Unknown"
            let secs = Int(events[index].timestamp.timeIntervalSince(events[index + 2].timestamp).rounded())
            return "Ping-pong — bounced \(prior) → \(mid) → \(now) within \(secs)s"

        case .slowRoam:
            let prevAP = events[index + 1].apName ?? events[index + 1].bssid ?? "Unknown"
            let gap = Int(events[index].timestamp.timeIntervalSince(events[index + 1].timestamp).rounded())
            return "Slow roam — \(gap)s disconnect between \(prevAP) sessions"

        case .none:
            return ""
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remMin = minutes % 60
        return remMin == 0 ? "\(hours)h" : "\(hours)h \(remMin)m"
    }

    // MARK: Posting

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(req) { err in
            if let err = err { NSLog("WhichAP: notification add failed: \(err)") }
        }
    }
}

/// Internal alias so RoamNotifier doesn't need to fully-qualify everywhere.
typealias ProblemFlagAlias = ConnectionAnalysis.ProblemFlag

// MARK: - ReachabilityMonitor

/// Detects "connected to Wi-Fi but no real internet" (captive portal,
/// silent blackhole, broken upstream) using a passive `NWPathMonitor`
/// baseline plus HTTP probes — the same pattern macOS itself uses for
/// captive-portal detection. Probes fire on association change, wake from
/// sleep, and every 60 seconds as a safety net so a mid-session WAN-down
/// is noticed within a minute. Steady-state traffic: one ~1 KB probe to
/// captive.apple.com per minute.
///
/// State is exposed via `current` and via `delegate?.reachabilityDidChange`.
/// Probe targets `http://captive.apple.com/hotspot-detect.html` and looks
/// for "Success" in the response body. HTTP (not HTTPS) so captive portals
/// can intercept and redirect.
protocol ReachabilityMonitorDelegate: AnyObject {
    func reachabilityDidChange(_ reachability: InternetReachability)
}

final class ReachabilityMonitor {
    private static let probeURL = URL(string: "http://captive.apple.com/hotspot-detect.html")!
    private static let probeTimeout: TimeInterval = 5.0
    private static let failureThreshold = 2
    private static let ipProbeURL = URL(string: "https://icanhazip.com")!
    private static let ipProbeTimeout: TimeInterval = 5.0
    private static let periodicInterval: TimeInterval = 60.0

    private let monitorQueue = DispatchQueue(label: "com.grangerchurch.whichap.reachability")
    private var pathMonitor: NWPathMonitor?
    private var lastPathStatus: NWPath.Status?
    private var consecutiveFailures = 0
    private var probeTask: URLSessionDataTask?
    private var ipProbeTask: URLSessionDataTask?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var periodicTimer: Timer?
    private var isRunning = false

    weak var delegate: ReachabilityMonitorDelegate?

    private(set) var current: InternetReachability = .unknown {
        didSet {
            guard oldValue != current else { return }
            // Drop any stale external IP whenever we're not confidently reachable.
            if current != .reachable {
                ipProbeTask?.cancel()
                ipProbeTask = nil
                externalIP = nil
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.reachabilityDidChange(self.current)
            }
        }
    }

    /// Public-facing IPv4 address from icanhazip.com. Refreshed only when
    /// there's a reason to: association change, wake from sleep, or a
    /// captive verdict that just flipped to `.reachable`. The 60-second
    /// safety-net captive probe does NOT re-fetch the IP. Cleared when the
    /// verdict flips away from `.reachable`. Decorative — failures here
    /// silently leave the value as nil.
    private(set) var externalIP: String? {
        didSet {
            guard oldValue != externalIP else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.reachabilityDidChange(self.current)
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        consecutiveFailures = 0
        lastPathStatus = nil
        current = .unknown

        // NWPathMonitor instances cannot be restarted after cancel; create fresh.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        monitor.start(queue: monitorQueue)
        pathMonitor = monitor

        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            self?.handleWillSleep()
        }
        wakeObserver = nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.handleDidWake()
        }
        schedulePeriodicTimer()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pathMonitor?.cancel()
        pathMonitor = nil
        probeTask?.cancel()
        probeTask = nil
        ipProbeTask?.cancel()
        ipProbeTask = nil
        cancelPeriodicTimer()
        let nc = NSWorkspace.shared.notificationCenter
        if let s = sleepObserver { nc.removeObserver(s) }
        if let w = wakeObserver { nc.removeObserver(w) }
        sleepObserver = nil
        wakeObserver = nil
        current = .unknown
    }

    private func schedulePeriodicTimer() {
        periodicTimer?.invalidate()
        let t = Timer(timeInterval: Self.periodicInterval, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }
            // Only probe when the OS-level path is usable — no point hitting
            // the network when NWPathMonitor already says "unsatisfied".
            if self.lastPathStatus == .satisfied {
                self.triggerProbe(refreshIP: false)
            }
        }
        t.tolerance = Self.periodicInterval * 0.1
        RunLoop.main.add(t, forMode: .common)
        periodicTimer = t
    }

    private func cancelPeriodicTimer() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    /// Called externally when the SSID or BSSID changes (Wi-Fi roam or
    /// reconnect) — those don't show up in NWPathMonitor since the path
    /// stays "satisfied" across most roams. We probe anyway so the verdict
    /// reflects the new association.
    func networkAssociationChanged() {
        guard isRunning else { return }
        triggerProbe(refreshIP: true)
    }

    private func handlePathUpdate(_ path: NWPath) {
        let prev = lastPathStatus
        lastPathStatus = path.status

        guard path.status == .satisfied else {
            // Hard failure: no usable path (link down, no DHCP, no route).
            consecutiveFailures = 0
            probeTask?.cancel()
            probeTask = nil
            current = .unreachable
            return
        }

        // Skip probing on cellular tethering / Low Data Mode — trust the OS
        // and don't burn the user's expensive bytes on a captive-portal probe.
        if path.isExpensive || path.isConstrained {
            current = .reachable
            return
        }

        // Probe on the .unsatisfied → .satisfied transition (or first start).
        if prev != .satisfied {
            triggerProbe(refreshIP: true)
        }
    }

    private func handleWillSleep() {
        probeTask?.cancel()
        probeTask = nil
        ipProbeTask?.cancel()
        ipProbeTask = nil
        cancelPeriodicTimer()
        // Leave `current` at last-known so the menu bar doesn't flicker on
        // sleep — the wake handler will re-probe and refresh.
    }

    private func handleDidWake() {
        guard isRunning else { return }
        schedulePeriodicTimer()
        triggerProbe(refreshIP: true)
    }

    private func triggerProbe(refreshIP: Bool) {
        probeTask?.cancel()
        var req = URLRequest(url: Self.probeURL)
        req.httpMethod = "GET"
        req.timeoutInterval = Self.probeTimeout
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            self?.handleProbeResult(data: data, response: response, error: error, refreshIP: refreshIP)
        }
        probeTask = task
        task.resume()
    }

    private func handleProbeResult(data: Data?, response: URLResponse?, error: Error?, refreshIP: Bool) {
        if let error = error {
            // Treat user-cancellation as a no-op (we cancelled to start a new probe).
            if (error as NSError).code == NSURLErrorCancelled { return }
            failProbe()
            return
        }
        guard let data, let body = String(data: data, encoding: .utf8) else {
            failProbe()
            return
        }
        if body.contains("Success") {
            let wasNotReachable = (current != .reachable)
            consecutiveFailures = 0
            current = .reachable
            // Refresh IP if the caller explicitly asked (association change,
            // wake from sleep) or if the verdict just flipped from non-reachable
            // → reachable (captive cleared, WAN came back) — both imply egress
            // may have changed. Periodic ticks skip this to keep traffic to
            // icanhazip.com near zero at steady state.
            if refreshIP || wasNotReachable {
                triggerIPProbe()
            }
        } else {
            // Apple's well-known body is exactly "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>".
            // Anything else means a captive portal or proxy intercepted and rewrote the response.
            consecutiveFailures = 0
            current = .captive
        }
    }

    private func failProbe() {
        consecutiveFailures += 1
        if consecutiveFailures >= Self.failureThreshold {
            current = .unreachable
        }
    }

    private func triggerIPProbe() {
        ipProbeTask?.cancel()
        var req = URLRequest(url: Self.ipProbeURL)
        req.httpMethod = "GET"
        req.timeoutInterval = Self.ipProbeTimeout
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            self?.handleIPProbeResult(data: data, response: response, error: error)
        }
        ipProbeTask = task
        task.resume()
    }

    private func handleIPProbeResult(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            if (error as NSError).code == NSURLErrorCancelled { return }
            return  // missing IP just hides the parenthetical; no retry
        }
        guard let data, let body = String(data: data, encoding: .utf8) else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // Sanity: icanhazip returns a bare IP (max 45 chars for IPv6). Anything
        // longer or containing HTML is a captive-portal redirect — discard.
        guard !trimmed.isEmpty, trimmed.count <= 45, !trimmed.contains("<") else { return }
        // Ignore stale results that arrive after a verdict flip.
        guard current == .reachable else { return }
        externalIP = trimmed
    }
}
