//
//  GWBtEvent.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 08/03/24.
//

import CoreBluetooth
import Foundation

struct GWEventData: Encodable {
    let eventDescription: String
    let level: String
    let date: String

    init(from event: GWBtEvent) {
        self.eventDescription = event.description
        self.date = Date.now.ISO8601Format()
        self.level = String(describing: event.level)
    }
}

enum LogLevel {
    case info, warn, error
}

enum GWBtEvent {
    case initialized
    case willStartScanning
    case notPoweredOn
    case newStatus(GWStatus)
    case newCBState(CBManagerState)
    case startingScan
    case discoveredPeripheral
    case hgDeviceFound
    case scanStopped
    case tryingToConnect
    case deviceConnected(String?)
    case deviceDisconnected(String?)
    case discoveringServices
    case serviceDiscovered
    case discoveringCharacteristics(service: String)
    case characteristicsDiscovered
    case newValue(GWServiceCharacteristic)
    case characteristicNotified(String)
    case gwBtStopped
    case sendingReport
    case reportSent
    case gwError(GWError)
    case baseUrlUpdated(String)
    case writtenValue(Int, String)
    case receivedSerial(String, String)
    case writtenFw(Int, String)

    var level: LogLevel {
        switch self {
        case .initialized: return .info
        case .willStartScanning: return .info
        case .notPoweredOn: return .info
        case .newStatus(let gwStatus): return gwStatus.level
        case .newCBState(_): return .info
        case .startingScan: return .info
        case .discoveredPeripheral: return .info
        case .hgDeviceFound: return .info
        case .scanStopped: return .warn
        case .tryingToConnect: return .info
        case .deviceConnected(_): return .info
        case .deviceDisconnected(_): return .info
        case .discoveringServices: return .info
        case .serviceDiscovered: return .info
        case .discoveringCharacteristics: return .info
        case .characteristicsDiscovered: return .info
        case .newValue(_): return .info
        case .characteristicNotified(_): return .info
        case .gwBtStopped: return .warn
        case .sendingReport: return .info
        case .reportSent: return .info
        case .gwError(_): return .error
        case .baseUrlUpdated(_): return .info
        case .writtenValue(_, _): return .info
        case .receivedSerial(_, _): return .info
        case .writtenFw(_, _): return .info
        }
    }

    var description: String {
        switch self {
        case let .newStatus(gwStatus):
            return "newStatus: \(String(describing: gwStatus))"
        case let .newCBState(cbState):
            return "newCBState: \(cbState.description)"
        case let .deviceConnected(deviceName):
            return "deviceConnected: \(deviceName ?? "Unknown")"
        case let .deviceDisconnected(deviceName):
            return "deviceConnected: \(deviceName ?? "Unknown")"
        case let .discoveringCharacteristics(service: service):
            return "discoveringCharacteristics for service: \(service)"
        case let .newValue(characteristic):
            return "newValue for characteristic \(characteristic)"
        case let .characteristicNotified(uuid):
            return "Received Notify from \(uuid)"
        case let .gwError(gwError):
            return gwError.description
        case let .baseUrlUpdated(newUrl):
            return "new baseUrl: \(newUrl)"
        case let .writtenValue(length, device):
            return "written \(length) bytes on \(device)"
        case let .receivedSerial(serial, peripheral):
            return "peripheral \(peripheral) informed serial \(serial)"
        case let .writtenFw(length, device):
            return "written FW with \(length) bytes on \(device)"
        default: return String(describing: self)
        }
    }
}

extension CBManagerState {
    var description: String {
        switch self {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unknown"
        }
    }
}
