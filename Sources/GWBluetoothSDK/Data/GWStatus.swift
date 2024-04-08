//
//  GWStatus.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 08/03/24.
//

import CoreBluetooth
import Foundation

public enum GWStatus {
    case unauthorized,
         poweredOff,
         failure(String),
         disconnectedAndScanning,
         connected,
         stopped

    var level: LogLevel {
        switch self {
        case .unauthorized: return .error
        case .poweredOff: return .warn
        case .failure(_): return .error
        case .disconnectedAndScanning: return .info
        case .connected: return .info
        case .stopped: return .warn
        }
    }
}

extension CBManagerState {
    func convertToGwStatus() -> GWStatus {
        switch self {
        case .unknown: return .disconnectedAndScanning
        case .resetting: return .disconnectedAndScanning
        case .unsupported: return .unauthorized
        case .unauthorized: return .unauthorized
        case .poweredOff: return .poweredOff
        case .poweredOn: return .disconnectedAndScanning
        @unknown default: return .disconnectedAndScanning
        }
    }
}
