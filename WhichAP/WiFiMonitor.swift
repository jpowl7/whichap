import Foundation
import CoreWLAN
import CoreLocation

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

    /// Signal strength as a percentage (0–100).
    var signalPercent: Int {
        return max(0, min(100, 2 * (100 + rssi)))
    }

    /// Noise floor as a percentage (0–100), where lower is better.
    var noisePercent: Int {
        // Noise is typically -80 to -100 dBm; map to 0-100 where 0% = -100, 100% = 0
        return max(0, min(100, 100 + noise))
    }

    /// Human-readable signal quality derived from RSSI.
    var signalQuality: SignalQuality {
        return SignalQuality(rssi: rssi)
    }
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
}

// MARK: - ConnectionHistoryStore

final class ConnectionHistoryStore {
    static let shared = ConnectionHistoryStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
}

// MARK: - WiFiMonitor

final class WiFiMonitor: NSObject, CLLocationManagerDelegate {

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
    private var bssidStableSince: Date?

    /// When the current AP connection started (BSSID first seen or changed)
    private(set) var connectedToAPSince: Date?

    /// History of AP connections, newest first
    private(set) var connectionHistory: [ConnectionEvent] = [] {
        didSet { ConnectionHistoryStore.shared.save(connectionHistory) }
    }

    private(set) var locationAuthorized: Bool = false
    private(set) var latestInfo: WiFiConnectionInfo?

    // MARK: Lifecycle

    override init() {
        super.init()
        connectionHistory = ConnectionHistoryStore.shared.load()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        startPolling(interval: PollInterval.disconnected)
    }

    deinit {
        stopPolling()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        locationAuthorized = (status == .authorizedAlways || status == .authorized)
        poll()
    }

    // MARK: Polling

    private func startPolling(interval: TimeInterval) {
        stopPolling()
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(pollFired), userInfo: nil, repeats: true)
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc private func pollFired() {
        poll()
    }

    func clearHistory() {
        connectionHistory.removeAll()
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
                bssidStableSince = nil
                connectedToAPSince = nil
                startPolling(interval: PollInterval.disconnected)
            }
            return
        }

        let currentBSSID = info.bssid

        if currentBSSID != lastBSSID {
            // BSSID changed — record history event and enter roaming state
            let now = Date()
            let apName = currentBSSID.flatMap { BSSIDMapping.shared.apName(forBSSID: $0) }
            let event = ConnectionEvent(
                timestamp: now,
                ssid: info.ssid,
                bssid: currentBSSID,
                apName: apName,
                rssi: info.rssi,
                band: info.band
            )
            connectionHistory.insert(event, at: 0)
            // Keep last 100 events
            if connectionHistory.count > 100 {
                connectionHistory = Array(connectionHistory.prefix(100))
            }

            lastBSSID = currentBSSID
            bssidStableSince = now
            connectedToAPSince = now
            if pollState != .roaming {
                pollState = .roaming
                startPolling(interval: PollInterval.roaming)
            }
        } else if pollState == .roaming {
            // Same BSSID; check if we've been stable long enough
            if let stableSince = bssidStableSince,
               Date().timeIntervalSince(stableSince) >= PollInterval.roamingSettleTime {
                pollState = .stable
                startPolling(interval: PollInterval.stable)
            }
        } else if pollState == .disconnected {
            // Transitioned from disconnected to connected
            let now = Date()
            let apName = currentBSSID.flatMap { BSSIDMapping.shared.apName(forBSSID: $0) }
            let event = ConnectionEvent(
                timestamp: now,
                ssid: info.ssid,
                bssid: currentBSSID,
                apName: apName,
                rssi: info.rssi,
                band: info.band
            )
            connectionHistory.insert(event, at: 0)
            if connectionHistory.count > 100 {
                connectionHistory = Array(connectionHistory.prefix(100))
            }

            lastBSSID = currentBSSID
            bssidStableSince = now
            connectedToAPSince = now
            pollState = .stable
            startPolling(interval: PollInterval.stable)
        }
    }

    // MARK: CoreWLAN reading

    private func readWiFiInfo() -> WiFiConnectionInfo? {
        guard let interface = CWWiFiClient.shared().interface() else {
            return nil
        }

        // If there is no SSID the interface is likely disconnected.
        guard interface.ssid() != nil else {
            return nil
        }

        let ssid = interface.ssid()
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
            locationAuthorized: locationAuthorized,
            phyMode: phyMode,
            security: security,
            ipAddress: ipAddress
        )
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
