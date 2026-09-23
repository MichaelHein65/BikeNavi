import Foundation
import CoreBluetooth
import Combine

/// Shared, read-only bike connection for the ride screen and connection details.
/// Never sends bike-control commands or writes characteristic values.
final class BikeBluetoothService: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum Consumer { case rideScreen, activeRide, diagnostics }
    var onMeasurement: ((BikeMeasurement) -> Void)?
    private var consumers: Set<Consumer> = []
    struct Candidate: Identifiable {
        let id: UUID
        let name: String
        let source: String
    }
    @Published var status = "Bike nicht verbunden"
    @Published var running = false
    @Published var connected = false
    @Published var candidates: [Candidate] = []
    @Published var battery: Int?
    @Published var batteryAt: Date?
    @Published var batteryReceivedInCurrentConnection = false
    @Published var connectedAt: Date?
    @Published var lastTelemetryAt: Date?
    @Published var riderPower: Int?
    @Published var powerAt: Date?
    @Published var motorPower: Int?
    @Published var motorPowerAt: Date?
    @Published var assistMode: Int?
    @Published var assistModeAt: Date?
    @Published var cadence: Int?
    @Published var speed: Double?
    @Published var packets = 0
    @Published var rawPackets = 0
    @Published var messages: [String] = []
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var selected: CBPeripheral?
    private var liveCharacteristic: CBCharacteristic?
    private var refresh: Timer?
    private var discoveryDeadline: Date?
    private var connectingAt: Date?
    private var lastRawLog = Date.distantPast
    private var lastRoutineLog = Date.distantPast
    private var lastSnapshot = Date.distantPast
    private var retryAfter = Date.distantPast
    private var smartphoneChannelReady = false
    private let liveUUID = CBUUID(string: "0000eb21-eaa2-11e9-81b4-2a2ae2dbcce4")
    // Notification-only telemetry channels observed in Bosch smartphone clients.
    // Their framing differs from the documented LDI protobuf.
    private let smartphoneUUIDs = ["00000011", "0000eb11"].map {
        CBUUID(string: "\($0)-eaa2-11e9-81b4-2a2ae2dbcce4")
    }
    private let serviceUUIDs = ["00000010", "00000020", "00000040", "0000eb10", "0000eb20", "0000eb40", "0000eb60", "0000eba0", "0000ebd0"].map {
        CBUUID(string: "\($0)-eaa2-11e9-81b4-2a2ae2dbcce4")
    }
    private let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BikeBluetooth", isDirectory: true)
    var logURL: URL { folder.appendingPathComponent("events.jsonl") }

    override init() {
        super.init()
        if let saved = UserDefaults.standard.string(forKey: "BoschTestBikeIdentifier"), let id = UUID(uuidString: saved) {
            restoreBattery(for: id)
        }
    }

    private func restoreBattery(for id: UUID) {
        battery = nil; batteryAt = nil; batteryReceivedInCurrentConnection = false
        let key = "BoschBatteryReading.\(id.uuidString)"
        var reading = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(BikeBatteryReading.self, from: $0) }
        if reading?.isValid(for: id) != true {
            let migrated = "BoschBatteryLogMigrated.\(id.uuidString)"
            if !UserDefaults.standard.bool(forKey: migrated) {
                let logs = [folder.appendingPathComponent("previous.jsonl"), logURL].compactMap { try? Data(contentsOf: $0) }
                reading = BikeBatteryReading.recover(from: logs, for: id)
                if let reading, let data = try? JSONEncoder().encode(reading) { UserDefaults.standard.set(data, forKey: key) }
                UserDefaults.standard.set(true, forKey: migrated)
            }
        }
        if let reading, reading.isValid(for: id) { battery = reading.percent; batteryAt = reading.sampledAt }
    }

    private func receiveBattery(_ percent: Int, at date: Date) {
        guard let id = selected?.identifier else { return }
        battery = percent; batteryAt = date; batteryReceivedInCurrentConnection = true
        let reading = BikeBatteryReading(bikeID: id, percent: percent, sampledAt: date)
        if let data = try? JSONEncoder().encode(reading) {
            UserDefaults.standard.set(data, forKey: "BoschBatteryReading.\(id.uuidString)")
        }
    }

    func monitor(_ enabled: Bool, for consumer: Consumer) {
        if enabled { consumers.insert(consumer) } else { consumers.remove(consumer) }
        if consumers.isEmpty { stop() } else { start() }
    }

    func retry() {
        guard running, !connected else { return }
        retryAfter = .distantPast
        if selected == nil { beginDiscovery() }
    }

    private func start() {
        guard !running else { return }
        candidates = []; peripherals = [:]
        running = true
        status = "Bluetooth wird vorbereitet"
        record("start", ["source": "direct_iPhone_BLE"])
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else { centralManagerDidUpdateState(central!) }
        refresh = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func stop() {
        guard running else { return }
        running = false
        refresh?.invalidate(); refresh = nil
        central?.stopScan()
        if let selected { central?.cancelPeripheralConnection(selected) }
        selected = nil; liveCharacteristic = nil; connectingAt = nil
        smartphoneChannelReady = false
        connected = false
        status = "Bike nicht verbunden"
        record("stopped")
    }

    func connect(_ id: UUID) {
        guard running, let central, central.state == .poweredOn, let peripheral = peripherals[id] else { return }
        if selected?.identifier == id { return }
        if let old = selected { central.cancelPeripheralConnection(old) }
        selected = peripheral
        liveCharacteristic = nil
        restoreBattery(for: id)
        riderPower = nil; powerAt = nil; cadence = nil; speed = nil
        connectedAt = nil; lastTelemetryAt = nil
        motorPower = nil; motorPowerAt = nil; assistMode = nil; assistModeAt = nil
        connected = false; packets = 0; rawPackets = 0
        smartphoneChannelReady = false
        UserDefaults.standard.set(id.uuidString, forKey: "BoschTestBikeIdentifier")
        peripheral.delegate = self
        central.stopScan()
        connectingAt = Date()
        status = "Verbindung mit \(peripheral.name ?? "Bosch Bike") …"
        record("connecting", ["id": id.uuidString])
        central.connect(peripheral)
    }

    private func beginDiscovery() {
        guard running, selected == nil, let central, central.state == .poweredOn else { return }
        retrieveConnected()
        if selected == nil, let value = UserDefaults.standard.string(forKey: "BoschTestBikeIdentifier"),
           let id = UUID(uuidString: value),
           let remembered = central.retrievePeripherals(withIdentifiers: [id]).first {
            add(remembered, source: "Dein gespeichertes Bike")
        }
        guard selected == nil else { return }
        status = "Suche dein Bosch Bike …"
        discoveryDeadline = Date().addingTimeInterval(45)
        // Some Bosch smartphone advertisements omit their service UUIDs.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        record("scan_started")
    }

    private func retrieveConnected() {
        guard let central else { return }
        for peripheral in central.retrieveConnectedPeripherals(withServices: serviceUUIDs) {
            add(peripheral, source: "Bereits mit dem iPhone verbunden")
        }
    }

    private func add(_ peripheral: CBPeripheral, source: String) {
        peripherals[peripheral.identifier] = peripheral
        if !candidates.contains(where: { $0.id == peripheral.identifier }) {
            candidates.append(Candidate(id: peripheral.identifier, name: peripheral.name ?? "Bosch Bike", source: source))
            if selected == nil { status = "Bike gefunden – bitte auswählen" }
            record("candidate", ["id": peripheral.identifier.uuidString, "name": peripheral.name ?? "", "source": source])
        }
        if selected == nil, Date() >= retryAfter,
           UserDefaults.standard.string(forKey: "BoschTestBikeIdentifier") == peripheral.identifier.uuidString {
            connect(peripheral.identifier)
        }
    }

    private func tick() {
        guard running else { return }
        if let selected, selected.state == .connected, let liveCharacteristic {
            if let connectedAt, Date().timeIntervalSince(connectedAt) > 10, lastTelemetryAt == nil {
                status = smartphoneChannelReady
                    ? "Verbunden, aber noch keine Bike-Daten. Bosch Flow öffnen, dann zu BikeNavi zurückkehren."
                    : "Verbunden – Smartphone-Datenkanal wird vorbereitet"
            }
            // The smartphone status stream carries our data. Avoid repeated empty LDI reads.
            if rawPackets == 0, liveCharacteristic.properties.contains(.read) { selected.readValue(for: liveCharacteristic) }
        } else if let selected, let connectingAt, Date().timeIntervalSince(connectingAt) > 25 {
            self.connectingAt = nil
            central?.cancelPeripheralConnection(selected)
            retryAfter = Date().addingTimeInterval(10)
            status = "Verbindung nicht zustande gekommen. Erneut versuchen."
            record("connection_timeout")
        } else if selected == nil, central?.state == .poweredOn {
            if Date() >= retryAfter { beginDiscoveryIfNeeded() }
            if let discoveryDeadline, Date() >= discoveryDeadline {
                central?.stopScan()
                self.discoveryDeadline = nil
                if candidates.isEmpty { status = "Noch kein Bike gefunden. Flow verbinden, danach Suche neu starten." }
                record("scan_finished", ["candidates": candidates.count])
            }
        }
        snapshot()
    }

    private func beginDiscoveryIfNeeded() {
        if central?.isScanning == true { retrieveConnected() }
        else { beginDiscovery() }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        record("bluetooth_state", ["state": central.state.rawValue])
        switch central.state {
        case .poweredOn: if running { beginDiscovery() }
        case .poweredOff: connected = false; status = "Bitte Bluetooth am iPhone einschalten"
        case .unauthorized: connected = false; status = "Bluetooth-Zugriff in den iPhone-Einstellungen erlauben"
        case .unsupported: connected = false; status = "Bluetooth wird auf diesem Gerät nicht unterstützt"
        default: connected = false; status = "Bluetooth noch nicht bereit"
        }
        snapshot()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "").lowercased()
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard name.contains("smart system ebike") || services.contains(where: serviceUUIDs.contains) else { return }
        add(peripheral, source: "In der Nähe · \(RSSI) dBm")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard running, selected?.identifier == peripheral.identifier else { central.cancelPeripheralConnection(peripheral); return }
        connectingAt = nil; connected = true; connectedAt = Date()
        status = "Verbunden – verfügbare Daten werden geprüft"
        record("connected", ["id": peripheral.identifier.uuidString, "writeMTU": peripheral.maximumWriteValueLength(for: .withResponse)])
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        connectingAt = nil; connected = false; selected = nil
        retryAfter = Date().addingTimeInterval(10)
        status = "Verbindung fehlgeschlagen"
        record("connection_failed", ["error": error?.localizedDescription ?? "unknown"])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        connected = false; selected = nil; liveCharacteristic = nil; connectingAt = nil
        smartphoneChannelReady = false
        status = running ? "Bike getrennt – Verbindung wird wiederhergestellt" : "Bike nicht verbunden"
        record("disconnected", ["error": error?.localizedDescription ?? "none"])
        if running, Date() >= retryAfter { beginDiscovery() }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard selected?.identifier == peripheral.identifier, running else { return }
        if let error { record("services_error", ["error": error.localizedDescription]); return }
        let services = peripheral.services ?? []
        record("services", ["uuids": services.map { $0.uuid.uuidString }])
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
        if !services.contains(where: { $0.uuid == serviceUUIDs[4] }) {
            status = "Verbunden; dokumentierter Live-Datendienst fehlt"
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard selected?.identifier == peripheral.identifier, running else { return }
        if let error { record("characteristics_error", ["error": error.localizedDescription]); return }
        for characteristic in service.characteristics ?? [] {
            record("characteristic", ["service": service.uuid.uuidString, "uuid": characteristic.uuid.uuidString, "properties": characteristic.properties.rawValue])
            if characteristic.uuid == liveUUID {
                liveCharacteristic = characteristic
                status = "Live-Datendienst gefunden – warte auf Messwerte"
                if characteristic.properties.contains(.notify) { peripheral.setNotifyValue(true, for: characteristic) }
                if characteristic.properties.contains(.read) { peripheral.readValue(for: characteristic) }
            } else if smartphoneUUIDs.contains(characteristic.uuid), characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if service.uuid == CBUUID(string: "180A"), ["2A26", "2A27", "2A28", "2A29", "2A24"].contains(characteristic.uuid.uuidString), characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard running, selected?.identifier == peripheral.identifier else { return }
        if smartphoneUUIDs.contains(characteristic.uuid), characteristic.isNotifying, error == nil {
            smartphoneChannelReady = true
        }
        record("notification_state", ["uuid": characteristic.uuid.uuidString, "enabled": characteristic.isNotifying, "error": error?.localizedDescription ?? "none"])
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard running, selected?.identifier == peripheral.identifier else { return }
        if let error {
            status = "Verbunden, Datenzugriff fehlgeschlagen"
            record("read_error", ["uuid": characteristic.uuid.uuidString, "error": error.localizedDescription]); return
        }
        guard let data = characteristic.value else { return }
        if smartphoneUUIDs.contains(characteristic.uuid) {
            guard !data.isEmpty else { return }
            rawPackets += 1
            if packets == 0 { status = "Smartphone-Daten empfangen – Auswertung läuft" }
            if characteristic.uuid == smartphoneUUIDs[0] {
                do {
                    let decoded = try BoschSmartphoneData.decode(data)
                    let now = Date()
                    if let value = decoded.batteryPercent { receiveBattery(value, at: now) }
                    if let value = decoded.riderPowerWatts { riderPower = value; powerAt = now }
                    if let value = decoded.motorPowerWatts { motorPower = value; motorPowerAt = now }
                    if let value = decoded.assistMode { assistMode = value; assistModeAt = now }
                    if decoded != BoschSmartphoneData() {
                        onMeasurement?(BikeMeasurement(bikeID: peripheral.identifier, timestamp: now.timeIntervalSince1970,
                            batteryPercent: decoded.batteryPercent, riderPowerWatts: decoded.riderPowerWatts,
                            motorPowerWatts: decoded.motorPowerWatts, assistMode: decoded.assistMode))
                        packets += 1
                        lastTelemetryAt = now
                        status = "Bike-Daten direkt über Bluetooth empfangen"
                    }
                } catch {
                    record("smartphone_decode_error", ["bytes": data.count, "hex": data.prefix(512).map { String(format: "%02x", $0) }.joined()])
                }
            }
            record("smartphone_data", ["uuid": characteristic.uuid.uuidString, "bytes": data.count,
                                        "hex": data.prefix(1024).map { String(format: "%02x", $0) }.joined()])
            return
        }
        guard characteristic.uuid == liveUUID else {
            record("device_info", ["uuid": characteristic.uuid.uuidString, "value": String(data: data, encoding: .utf8) ?? ""]); return
        }
        guard !data.isEmpty else {
            if packets == 0 && rawPackets == 0 {
                status = smartphoneChannelReady
                    ? "Verbunden, aber noch keine Bike-Daten. Bosch Flow öffnen, dann zu BikeNavi zurückkehren."
                    : "Verbunden – Smartphone-Datenkanal wird vorbereitet"
            }
            record("empty_live_data"); return
        }
        do {
            let decoded = try BoschLiveData.decode(data)
            let now = Date()
            if let value = decoded.batteryPercent { receiveBattery(value, at: now) }
            if let value = decoded.riderPowerWatts { riderPower = value; powerAt = now }
            if let value = decoded.cadenceRPM { cadence = value }
            if let value = decoded.speedKPH { speed = value }
            packets += 1
            if decoded != BoschLiveData() {
                lastTelemetryAt = now
                onMeasurement?(BikeMeasurement(bikeID: peripheral.identifier, timestamp: now.timeIntervalSince1970,
                    batteryPercent: decoded.batteryPercent, riderPowerWatts: decoded.riderPowerWatts,
                    cadenceRPM: decoded.cadenceRPM, speedKPH: decoded.speedKPH, chargerConnected: decoded.chargerConnected))
            }
            status = batteryAt == nil ? "Live-Daten empfangen, noch kein Akkustand" : "Bike-Daten direkt über Bluetooth empfangen"
            if now.timeIntervalSince(lastRawLog) >= 1 {
                lastRawLog = now
                record("live_data", ["hex": data.map { String(format: "%02x", $0) }.joined(), "bytes": data.count])
            } else { snapshot() }
        } catch {
            record("decode_error", ["bytes": data.count, "hex": data.prefix(512).map { String(format: "%02x", $0) }.joined()])
        }
    }

    private func record(_ event: String, _ details: [String: Any] = [:]) {
        let now = Date()
        // Full packet logs belong to the diagnostic screen, not every second of a tour.
        if !consumers.contains(.diagnostics), ["smartphone_data", "live_data", "empty_live_data"].contains(event) {
            if now.timeIntervalSince(lastRoutineLog) < 30 { snapshot(); return }
            lastRoutineLog = now
        }
        let line = "\(now.formatted(date: .omitted, time: .standard)) · \(event) \(details)"
        messages.append(line)
        if messages.count > 80 { messages.removeFirst(messages.count - 80) }
        var entry = details
        entry["event"] = event; entry["timestamp"] = now.timeIntervalSince1970
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let size = try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber, size.intValue > 1_000_000 {
                let previous = folder.appendingPathComponent("previous.jsonl")
                try? FileManager.default.removeItem(at: previous)
                try FileManager.default.moveItem(at: logURL, to: previous)
            }
            if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            var data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
            data.append(0x0a); try handle.write(contentsOf: data)
        } catch { NSLog("BikeBluetooth diagnostic log unavailable: %@", error.localizedDescription) }
        snapshot()
    }

    private func snapshot() {
        let now = Date()
        guard now.timeIntervalSince(lastSnapshot) >= 1 else { return }
        lastSnapshot = now
        var value: [String: Any] = ["source": "direct_iPhone_BLE", "timestamp": Date().timeIntervalSince1970,
                                  "status": status, "running": running, "connected": connected, "packets": packets, "rawPackets": rawPackets,
                                  "candidates": candidates.map { ["id": $0.id.uuidString, "name": $0.name, "source": $0.source] }]
        if let battery { value["batteryPercent"] = battery }
        if let batteryAt { value["batterySampledAt"] = batteryAt.timeIntervalSince1970 }
        value["batteryReceivedInCurrentConnection"] = batteryReceivedInCurrentConnection
        if let lastTelemetryAt { value["lastTelemetryAt"] = lastTelemetryAt.timeIntervalSince1970 }
        if let riderPower { value["riderPowerWatts"] = riderPower }
        if let powerAt { value["powerSampledAt"] = powerAt.timeIntervalSince1970 }
        if let motorPower { value["motorPowerWatts"] = motorPower }
        if let motorPowerAt { value["motorPowerSampledAt"] = motorPowerAt.timeIntervalSince1970 }
        if let assistMode { value["assistModeCode"] = assistMode }
        if let assistModeAt { value["assistModeSampledAt"] = assistModeAt.timeIntervalSince1970 }
        if let cadence { value["cadenceRPM"] = cadence }
        if let speed { value["speedKPH"] = speed }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]) {
            try? data.write(to: folder.appendingPathComponent("status.json"), options: .atomic)
        }
    }
}
