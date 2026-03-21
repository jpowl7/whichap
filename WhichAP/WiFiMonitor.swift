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

    /// Signal-to-noise ratio as a positive value.
    var snr: Int {
        return rssi - noise
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

    private(set) var locationAuthorized: Bool = false
    private(set) var latestInfo: WiFiConnectionInfo?

    // MARK: Lifecycle

    override init() {
        super.init()
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
                startPolling(interval: PollInterval.disconnected)
            }
            return
        }

        let currentBSSID = info.bssid

        if currentBSSID != lastBSSID {
            // BSSID changed — enter roaming state
            lastBSSID = currentBSSID
            bssidStableSince = Date()
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
            lastBSSID = currentBSSID
            bssidStableSince = Date()
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

        return WiFiConnectionInfo(
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            noise: noise,
            channelNumber: channelNumber,
            channelWidth: channelWidth,
            band: band,
            transmitRate: txRate,
            locationAuthorized: locationAuthorized
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
            return "2.4G"
        case .band5GHz:
            return "5G"
        case .band6GHz:
            return "6G"
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
}
