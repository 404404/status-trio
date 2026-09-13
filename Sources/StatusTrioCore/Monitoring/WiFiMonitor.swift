import CoreWLAN
import Foundation
import Network
import SystemConfiguration
import os

private let wifiMonitorLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "WiFiMonitor"
)

enum WiFiInterfaceMode: Equatable, Sendable {
    case none
    case station
    case ibss
    case hostAP
    case unknown

    init(coreWLANMode: CWInterfaceMode) {
        switch coreWLANMode {
        case .none:
            self = .none
        case .station:
            self = .station
        case .IBSS:
            self = .ibss
        case .hostAP:
            self = .hostAP
        @unknown default:
            self = .unknown
        }
    }
}

struct WiFiClassificationInput: Equatable, Sendable {
    var powerOn: Bool
    var serviceActive: Bool
    var mode: WiFiInterfaceMode
    var pathSatisfied: Bool?
    var pathUsesWiFi: Bool
    var pathExpensive: Bool
    var sharingActive: Bool
}

enum WiFiClassifier {
    static func classify(_ input: WiFiClassificationInput) -> WiFiState {
        if !input.powerOn { return .off }
        if !input.serviceActive { return .notAssociated }
        if input.sharingActive { return .shared }
        if input.mode == .ibss { return .temporary }

        if let pathSatisfied = input.pathSatisfied {
            if pathSatisfied && input.pathUsesWiFi && input.pathExpensive {
                return .hotspot
            }
            if !pathSatisfied {
                return .noInternet
            }
        }

        return .connected
    }
}

struct WiFiSystemReading: Equatable, Sendable {
    var powerOn: Bool
    var serviceActive: Bool
    var mode: WiFiInterfaceMode
    var rssi: Int?
    var ssid: String?
}

protocol WiFiSystemReadingProviding: AnyObject {
    func read() -> WiFiSystemReading?
}

protocol InternetSharingDetecting: AnyObject {
    func isActive() -> Bool?
}

protocol WiFiEventMonitoring: AnyObject {
    func start(delegate: any CWEventDelegate, events: [CWEventType])
    func restart(delegate: any CWEventDelegate, events: [CWEventType])
    func stop()
}

struct WiFiPathSnapshot: Equatable, Sendable {
    var satisfied = false
    var usesWiFi = false
    var expensive = false
}

struct WiFiPathUpdate: Equatable, Sendable {
    let sequence: UInt64
    let snapshot: WiFiPathSnapshot
}

protocol WiFiPathMonitoring: AnyObject {
    func start(
        queue: DispatchQueue,
        handler: @escaping (WiFiPathUpdate) -> Void
    )
    func cancel()
}

typealias WiFiClientFactory = () -> CWWiFiClient

final class CoreWLANWiFiSystemReader: WiFiSystemReadingProviding {
    private let client: CWWiFiClient

    init(client: CWWiFiClient = CWWiFiClient.shared()) {
        self.client = client
    }

    func read() -> WiFiSystemReading? {
        guard let interface = client.interface() else { return nil }

        return WiFiSystemReading(
            powerOn: interface.powerOn(),
            serviceActive: interface.serviceActive(),
            mode: WiFiInterfaceMode(coreWLANMode: interface.interfaceMode()),
            rssi: interface.rssiValue(),
            ssid: interface.ssid()
        )
    }
}

final class CoreWLANWiFiEventMonitor: WiFiEventMonitoring {
    private let clientFactory: WiFiClientFactory
    private var client: CWWiFiClient

    init(clientFactory: @escaping WiFiClientFactory = { CWWiFiClient() }) {
        self.clientFactory = clientFactory
        self.client = clientFactory()
    }

    func start(delegate: any CWEventDelegate, events: [CWEventType]) {
        configure(delegate: delegate, events: events)
    }

    func restart(delegate: any CWEventDelegate, events: [CWEventType]) {
        clear()
        client = clientFactory()
        configure(delegate: delegate, events: events)
    }

    func stop() {
        clear()
    }

    private func configure(delegate: any CWEventDelegate, events: [CWEventType]) {
        client.delegate = delegate
        for event in events {
            do {
                try client.startMonitoringEvent(with: event)
            } catch {
                wifiMonitorLogger.error(
                    "Failed to register CoreWLAN event \(event.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func clear() {
        client.delegate = nil
        do {
            try client.stopMonitoringAllEvents()
        } catch {
            wifiMonitorLogger.error(
                "Failed to clear CoreWLAN events: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

private final class PathSequenceGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func next() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }
}

final class NetworkWiFiPathMonitor: @unchecked Sendable, WiFiPathMonitoring {
    private let lock = NSLock()
    private let sequenceGenerator = PathSequenceGenerator()
    private var monitor: NWPathMonitor?
    private var handler: ((WiFiPathUpdate) -> Void)?

    func start(
        queue: DispatchQueue,
        handler: @escaping (WiFiPathUpdate) -> Void
    ) {
        let monitor = NWPathMonitor()
        lock.withLock {
            self.monitor = monitor
            self.handler = handler
        }
        monitor.pathUpdateHandler = { [weak self, weak monitor] path in
            guard
                let self,
                let monitor,
                self.lock.withLock({ self.monitor === monitor })
            else { return }
            let update = WiFiPathUpdate(
                sequence: self.sequenceGenerator.next(),
                snapshot: WiFiPathSnapshot(
                    satisfied: path.status == .satisfied,
                    usesWiFi: path.usesInterfaceType(.wifi),
                    expensive: path.isExpensive
                )
            )
            let handler = self.lock.withLock { self.handler }
            handler?(update)
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        let monitor = lock.withLock { () -> NWPathMonitor? in
            let monitor = self.monitor
            self.monitor = nil
            handler = nil
            return monitor
        }
        monitor?.cancel()
    }
}

/// `com.apple.nat` is an undocumented dynamic-store key used only as a
/// best-effort signal. Missing or unreadable data returns `nil`, which means
/// "not definitively sharing" and never assumes sharing is active.
final class SystemInternetSharingDetector: InternetSharingDetecting {
    func isActive() -> Bool? {
        guard
            let store = SCDynamicStoreCreate(
                nil,
                "StatusTrio" as CFString,
                nil,
                nil
            ),
            let value = SCDynamicStoreCopyValue(
                store,
                "com.apple.nat" as CFString
            ) as? [String: Any],
            let nat = value["NAT"] as? [String: Any]
        else { return nil }

        return booleanValue(nat["Enabled"])
    }

    private func booleanValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        if let value = value as? Int {
            return value == 1
        }
        return nil
    }
}

@MainActor
final class WiFiMonitor: NSObject, WiFiMonitoring, CWEventDelegate {
    private enum Lifecycle {
        case idle
        case running
        case stopped
    }

    let updates: AsyncStream<WiFiStatus>

    private static let monitoredEvents: [CWEventType] = [
        .powerDidChange,
        .ssidDidChange,
        .bssidDidChange,
        .linkDidChange,
        .linkQualityDidChange,
        .modeDidChange
    ]

    private let continuation: AsyncStream<WiFiStatus>.Continuation
    private let systemReader: any WiFiSystemReadingProviding
    private let sharingDetector: any InternetSharingDetecting
    private let nameAuthorizer: any WiFiNameAuthorizing
    private let eventMonitor: any WiFiEventMonitoring
    private let pathMonitor: any WiFiPathMonitoring
    private let pathQueue = DispatchQueue(label: "StatusTrio.WiFiPath")
    private let staleInterval: TimeInterval
    private let now: () -> Date

    private var latestPath: WiFiPathSnapshot?
    private var latestPathSequence: UInt64?
    private var lastValidStatus: WiFiStatus?
    private var lastValidDate: Date?
    private var lastRecoveryAttempt: Date?
    private var isPersistentReadFailure = false
    private var lifecycle = Lifecycle.idle

    init(
        systemReader: any WiFiSystemReadingProviding = CoreWLANWiFiSystemReader(),
        sharingDetector: any InternetSharingDetecting = SystemInternetSharingDetector(),
        nameAuthorizer: any WiFiNameAuthorizing = CoreLocationWiFiNameAuthorizer(),
        eventMonitor: any WiFiEventMonitoring = CoreWLANWiFiEventMonitor(),
        pathMonitor: any WiFiPathMonitoring = NetworkWiFiPathMonitor(),
        staleInterval: TimeInterval = 30,
        initialPath: WiFiPathSnapshot? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.systemReader = systemReader
        self.sharingDetector = sharingDetector
        self.nameAuthorizer = nameAuthorizer
        self.eventMonitor = eventMonitor
        self.pathMonitor = pathMonitor
        self.staleInterval = staleInterval
        self.latestPath = initialPath
        self.now = now
        (updates, continuation) = AsyncStream.makeStream()
        super.init()
        nameAuthorizer.onAccessChange = { [weak self] in
            self?.refresh()
        }
    }

    isolated deinit {
        guard lifecycle != .stopped else { return }
        teardown()
    }

    func start() {
        guard lifecycle == .idle else { return }
        lifecycle = .running

        eventMonitor.start(delegate: self, events: Self.monitoredEvents)
        startPathMonitoring()
        refresh()
    }

    func recover() {
        guard lifecycle == .running else { return }

        lastRecoveryAttempt = now()
        eventMonitor.restart(delegate: self, events: Self.monitoredEvents)
        pathMonitor.cancel()
        startPathMonitoring()
    }

    func requestNameAccess() {
        guard lifecycle == .running, nameAuthorizer.access == .notDetermined else { return }
        nameAuthorizer.requestAccess()
    }

    private func startPathMonitoring() {
        pathMonitor.start(queue: pathQueue) { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self, self.lifecycle == .running else { return }
                if let latestPathSequence = self.latestPathSequence,
                   update.sequence <= latestPathSequence {
                    return
                }
                self.latestPathSequence = update.sequence
                self.latestPath = update.snapshot
                self.refresh()
            }
        }
    }

    func stop() {
        guard lifecycle != .stopped else { return }
        lifecycle = .stopped
        teardown()
    }

    func refresh() {
        guard lifecycle != .stopped else { return }

        guard let reading = systemReader.read() else {
            publish(.unavailable, rssi: nil, ssid: nil, nameAccess: nameAuthorizer.access)
            return
        }

        lastRecoveryAttempt = nil
        isPersistentReadFailure = false

        let sharingActive: Bool
        if reading.powerOn && reading.serviceActive {
            sharingActive = sharingDetector.isActive() == true
        } else {
            sharingActive = false
        }

        let input = WiFiClassificationInput(
            powerOn: reading.powerOn,
            serviceActive: reading.serviceActive,
            mode: reading.mode,
            pathSatisfied: latestPath?.satisfied,
            pathUsesWiFi: latestPath?.usesWiFi ?? false,
            pathExpensive: latestPath?.expensive ?? false,
            sharingActive: sharingActive
        )
        let nameAccess = nameAuthorizer.access
        publish(
            WiFiClassifier.classify(input),
            rssi: normalizedRSSI(reading.rssi),
            ssid: nameAccess == .authorized ? normalizedSSID(reading.ssid) : nil,
            nameAccess: nameAccess
        )
    }

    nonisolated func clientConnectionInterrupted() {
        Task { @MainActor [weak self] in
            guard let self, self.lifecycle == .running else { return }
            self.refresh()
        }
    }

    nonisolated func clientConnectionInvalidated() {
        Task { @MainActor [weak self] in
            guard let self, self.lifecycle == .running else { return }
            self.recover()
            self.refresh()
        }
    }

    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    nonisolated func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    nonisolated func linkQualityDidChangeForWiFiInterface(
        withName interfaceName: String,
        rssi: Int,
        transmitRate: Double
    ) {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    nonisolated func modeDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    private func teardown() {
        eventMonitor.stop()
        pathMonitor.cancel()
        latestPath = nil
        latestPathSequence = nil
        lastValidStatus = nil
        lastValidDate = nil
        lastRecoveryAttempt = nil
        isPersistentReadFailure = false
        continuation.finish()
    }

    private func publish(
        _ state: WiFiState,
        rssi: Int?,
        ssid: String?,
        nameAccess: WiFiNameAccess
    ) {
        let candidate = WiFiStatus(
            state: state,
            rssi: rssi,
            ssid: ssid,
            nameAccess: nameAccess
        )

        if state == .unavailable {
            let currentDate = now()
            if
                let lastValidStatus,
                let lastValidDate,
                currentDate.timeIntervalSince(lastValidDate) <= staleInterval
            {
                continuation.yield(lastValidStatus)
                return
            }

            let shouldAttemptRecovery = lastValidStatus != nil || isPersistentReadFailure
            isPersistentReadFailure = true
            if shouldAttemptRecovery {
                recoverIfAllowed(at: currentDate)
            }

            lastValidStatus = nil
            lastValidDate = nil
            continuation.yield(candidate)
            return
        }

        isPersistentReadFailure = false
        lastValidStatus = candidate
        lastValidDate = now()
        continuation.yield(candidate)
    }

    private func recoverIfAllowed(at date: Date) {
        if
            let lastRecoveryAttempt,
            date.timeIntervalSince(lastRecoveryAttempt) < staleInterval
        {
            return
        }

        recover()
    }

    private func normalizedRSSI(_ rssi: Int?) -> Int? {
        guard let rssi, rssi < 0 else { return nil }
        return rssi
    }

    private func normalizedSSID(_ ssid: String?) -> String? {
        guard let ssid else { return nil }
        let value = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
