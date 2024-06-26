import Combine
import CoreBluetooth

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, ObservableObject {
    // MARK: - Internal properties

    @Published var isConnected = false
    let statusStream: DataStream<GWStatus> = .init()
    var lastSync: Date?
    var lastDataUpdate: Date?

    // MARK: - Private properties

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var gwBtStopped = false
    private let deviceBridge = DeviceSyncBridge()
    private let reportManager = GWReportManager.shared
    private var didReadSerial = false
    private let fwUpdater = FirmwareUpdater()
    private var ackCharacteristic: CBCharacteristic?
    private var searchDeviceTask: Task<Void, Never>?
    private var debugMode = false
    private var ongoingMessage: [GWServiceCharacteristic: Data] = [:]

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        reportManager.reportEvent(.initialized)
        statusStream.onEmit = { [weak self] newStatus in
            self?.reportManager.reportEvent(.newStatus(newStatus))
        }
        deviceBridge.onAckReceived = { [weak self] data in
            self?.onAckReceived(data)
        }
    }

    // MARK: - Public methods

    func startConnectionLoop() {
        gwBtStopped = false
        if let searchDeviceTask {
            searchDeviceTask.cancel()
        }
        searchDeviceTask = Task {
            while !gwBtStopped {
                if !isConnected, GWBluetooth.shared.env != nil {
                    startScanning()
                }
                do {
                    if #available(iOS 16.0, *) {
                        try await Task.sleep(for: .seconds(60))
                    } else {
                        try await Task.sleep(nanoseconds: 60 * 1000000000)
                    }
                } catch {
                    // When Task is cancelled, break loop
                    return
                }
            }
        }
    }

    func startScanning() {
        reportManager.reportEvent(.willStartScanning)
        guard let centralManager = centralManager, centralManager.state == .poweredOn else {
            isConnected = false
            reportManager.reportEvent(.notPoweredOn)
            statusStream.emit(centralManager?.state.convertToGwStatus() ?? .disconnectedAndScanning)
            return
        }

        guard
            let btUuidString = GWBluetooth.shared.env?.gwServerUUID,
            let gwBluetoothUUID = UUID(uuidString: btUuidString)
        else {
            statusStream.emit(.failure("Invalid service UUID"))
            return
        }

        centralManager.stopScan()

        reportManager.reportEvent(.startingScan)
        centralManager.scanForPeripherals(withServices: [CBUUID(nsuuid: gwBluetoothUUID)])
    }

    func stop() {
        if let connectedPeripheral {
            centralManager?.cancelPeripheralConnection(connectedPeripheral)
        }
        centralManager?.stopScan()
        gwBtStopped = true
        statusStream.emit(.stopped)
        reportManager.reportEvent(.gwBtStopped)
    }

    func setDebug(_ value: Bool) {
        debugMode = value
    }

    // MARK: - CB Central Manager

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        reportManager.reportEvent(.newCBState(central.state))
        if central.state == .poweredOn {
            startConnectionLoop()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        reportManager.reportEvent(.discoveredPeripheral)
        guard peripheral.name?.contains("HEALTHGATE") == true else {
            return
        }
        reportManager.reportEvent(.hgDeviceFound)
        centralManager?.stopScan()
        reportManager.reportEvent(.scanStopped)
        connectedPeripheral = peripheral
        reportManager.reportEvent(.tryingToConnect)
        GWReportManager.shared.btId = peripheral.identifier.uuidString
        centralManager?.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        reportManager.reportEvent(.deviceConnected(peripheral.name))
        statusStream.emit(.connected)
        isConnected = true
        peripheral.delegate = self
        connectedPeripheral = peripheral
        reportManager.reportEvent(.discoveringServices)
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if !gwBtStopped {
            reportManager.reportEvent(.deviceDisconnected)
            statusStream.emit(.disconnectedAndScanning)
        }
        isConnected = false
        connectedPeripheral = nil
        fwUpdater.cancelUpdate()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            statusStream.emit(.failure(error.localizedDescription))
            return
        }
        reportManager.reportEvent(.serviceDiscovered)
        guard let services = peripheral.services, !services.isEmpty else {
            statusStream.emit(.failure("No services found on connected device"))
            return
        }

        for service in services {
            reportManager.reportEvent(.discoveringCharacteristics(service: service.uuid.uuidString))
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            statusStream.emit(.failure("Error discovering characteristics: \(error.localizedDescription)"))
            return
        }
        reportManager.reportEvent(.characteristicsDiscovered)
        guard let characteristics = service.characteristics else {
            statusStream.emit(.failure("No characteristics found for service \(service.uuid)"))
            return
        }

        for characteristic in characteristics {
            if characteristic.uuid.uuidString == GWServiceCharacteristic.statusAck.rawValue {
                ackCharacteristic = characteristic
            }
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            handleReadError(error, for: characteristic)
            return
        }

        guard let gwCharacteristic = GWServiceCharacteristic(rawValue: characteristic.uuid.uuidString) else {
            statusStream.emit(.failure("Unknown characteristic: \(characteristic.uuid.uuidString)"))
            return
        }
        guard let data = characteristic.value else {
            statusStream.emit(.failure("Null data received for characteristic \(gwCharacteristic)"))
            return
        }
        reportManager.reportEvent(.newValue(gwCharacteristic))

        log("Received the following data for chr \(String(describing: gwCharacteristic)): \(data.base64EncodedString())")

        if gwCharacteristic == .serialFw {
            if !hasValidSerial(data) {
                guard let urlString = getValidURL(data) else {
                    statusStream.emit(.failure("Invalid URL for new FW"))
                    return
                }
                if !fwUpdater.hasUpdateInProgress() {
                    fwUpdater.startUpdate(peripheral, to: urlString, using: characteristic)
                }
            }
            return
        } else if gwCharacteristic == .statusAck {
            ongoingMessage[gwCharacteristic] = data
            sendCompleteMessage(gwCharacteristic)
            return
        }

        if msgIsEOF(data) {
            log("Finished read of \(String(describing: gwCharacteristic))")
            sendCompleteMessage(gwCharacteristic)
            return
        }

        if ongoingMessage[gwCharacteristic] != nil {
            log("Received next chunk for \(String(describing: gwCharacteristic))")
            ongoingMessage[gwCharacteristic]?.append(data)
        } else {
            log("Received first chunk for \(String(describing: gwCharacteristic)))")
            ongoingMessage[gwCharacteristic] = data
        }

        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            GWReportManager.shared.reportEvent(.gwError(.failedToWrite(error.localizedDescription)))
        } else {
            if
                let gwCharacteristic = GWServiceCharacteristic(rawValue: characteristic.uuid.uuidString),
                gwCharacteristic == .serialFw
            {
                fwUpdater.signalAck(for: characteristic)
            } else {
                GWReportManager.shared.reportEvent(.writtenValue(connectedPeripheral?.identifier.uuidString ?? "Unknown")
                )
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        reportManager.reportEvent(.characteristicNotified(characteristic.uuid.uuidString))
        peripheral.readValue(for: characteristic)
    }

    // MARK: - Private methods

    private func msgIsEOF(_ data: Data) -> Bool {
        data.count == 1 && data.first == 0x0
    }

    private func handleReadError(_ error: Error, for characteristic: CBCharacteristic) {
        // Disconsider random characteristics with read not allowed
        if error.localizedDescription.contains("not permitted") {
            return
        }
        statusStream.emit(.failure("Error updating value for characteristic \(characteristic.uuid.uuidString): \(error.localizedDescription)"))
        guard let gwChr = GWServiceCharacteristic(rawValue: characteristic.uuid.uuidString) else { return }
        if ongoingMessage[gwChr] != nil {
            ongoingMessage.removeValue(forKey: gwChr)
        }
    }

    private func sendCompleteMessage(_ characteristic: GWServiceCharacteristic) {
        guard let data = ongoingMessage[characteristic] else {
            GWReportManager.shared.reportEvent(.emptyChr(characteristic.rawValue))
            return
        }

        switch characteristic {
        case .statusAck, .dataParsed, .dataRaw, .logPrint, .logPacket:
            Task {
                await deviceBridge.handleMsg(data)
            }
        case .dataParsedV2, .serialFw:
            return
        }
        ongoingMessage[characteristic] = nil
    }

    private func onAckReceived(_ data: Data) {
        guard let ackCharacteristic else {
            GWReportManager.shared.reportEvent(.gwError(.failure("Does not contain ackCharacteristic stored to send ACK")))
            return
        }
        guard let connectedPeripheral else {
            GWReportManager.shared.reportEvent(.gwError(.failure("Tried to send ACK without connected peripheral")))
            return
        }
        connectedPeripheral.writeValue(data, for: ackCharacteristic, type: .withResponse)
    }

    private func getValidURL(_ data: Data) -> String? {
        guard
            let urlString = String(bytes: data, encoding: .utf8),
            urlString.contains("http"),
            URL(string: urlString) != nil
        else {
            return nil
        }
        return urlString
    }

    func convertDataToUIntString(_ data: Data) -> String? {
        // Serial has 6 bytes
        guard data.count == 6 else {
            return nil
        }

        // Complete the data with 2 bytes of padding
        var paddedData = Data([0, 0]) + data

        // Reverse the bytes to match little-endian format
        paddedData.reverse()

        // Ensure the data is correctly aligned
        guard paddedData.count == MemoryLayout<UInt64>.size else {
            return nil
        }

        // Load as UInt64
        let value = paddedData.withUnsafeBytes {
            $0.load(as: UInt64.self)
        }

        // Convert the UInt64 value to a string
        return String(value)
    }

    private func hasValidSerial(_ data: Data) -> Bool {
        guard
            let serial = convertDataToUIntString(data),
            serial.allSatisfy({ $0.isNumber }),
            serial.count <= 16
        else {
            return false
        }
        GWReportManager.shared.clientSerial = serial
        return true
    }

    private func log(_ message: String) {
        if debugMode {
            print(message)
        }
    }
}
