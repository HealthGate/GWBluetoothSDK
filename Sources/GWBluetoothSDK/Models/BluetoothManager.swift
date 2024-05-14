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
                        try await Task.sleep(nanoseconds: 60*1000000000)
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
        if let error = error {
            // Disconsider random characteristics with read not allowed
            if error.localizedDescription.contains("not permitted") {
                return
            }
            statusStream.emit(.failure("Error updating value for characteristic \(characteristic.uuid.uuidString): \(error.localizedDescription)"))
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

        if debugMode {
            print("Received the following data for chr \(String(describing: gwCharacteristic)): \(data.base64EncodedString())")
        }

        switch gwCharacteristic {
        case .statusAck, .dataParsed, .dataRaw, .logPrint, .logPacket:
            Task {
                await deviceBridge.handleMsg(data)
            }
        case .serialFw:
            if !hasValidSerial(data) {
                guard let urlString = getValidURL(data) else {
                    statusStream.emit(.failure("Invalid URL for new FW"))
                    return
                }
                fwUpdater.startUpdate(peripheral, to: urlString, using: characteristic)
            }
        case .dataParsedV2:
            print("Received dataParsedV2")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            GWReportManager.shared.reportEvent(.gwError(.failedToWrite(error.localizedDescription)))
        } else {
            GWReportManager.shared.reportEvent(.writtenValue(connectedPeripheral?.identifier.uuidString ?? "Unknown")
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        reportManager.reportEvent(.characteristicNotified(characteristic.uuid.uuidString))
        peripheral.readValue(for: characteristic)
    }

    // MARK: - Private methods

    private func onAckReceived(_ data: Data) {
        guard let ackCharacteristic else {
            GWReportManager.shared.reportEvent(.gwError(.failure("Does not contain ackCharacteristic stored to send ACK")))
            return
        }
        GWReportManager.shared.reportEvent(.writtenValue(data.count, connectedPeripheral?.identifier.uuidString ?? "Unknown"))
        connectedPeripheral?.writeValue(data, for: ackCharacteristic, type: .withResponse)
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

    private func hasValidSerial(_ data: Data) -> Bool {
        guard
            let serial = String(bytes: data, encoding: .utf8),
            serial.allSatisfy({ $0.isNumber }),
            serial.count <= 16
        else {
            return false
        }
        GWReportManager.shared.clientSerial = serial
        return true
    }
}
