//
//  FirmwareUpdater.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 07/04/24.
//

import CoreBluetooth
import Foundation

final class FirmwareUpdater {
    private let chunkSize = 1024
    private let service: ServiceProtocol
    private var characteristic: CBCharacteristic?
    private var ackContinuation: CheckedContinuation<Void, Never>?

    init(service: ServiceProtocol = Service.shared) {
        self.service = service
    }

    func startUpdate(
        _ peripheral: CBPeripheral,
        to fwUrl: String,
        using characteristic: CBCharacteristic
    ) {
        Task {
            let fwData = try await service.getFW(url: fwUrl)
            let dataChunks = splitIntoChunks(fwData)
            self.characteristic = characteristic
            await sendDataChunks(dataChunks, to: peripheral, using: characteristic)
        }
    }

    func signalAck(for characteristic: CBCharacteristic) {
        if characteristic == self.characteristic {
            ackContinuation?.resume()
        }
    }

    private func sendDataChunks(
        _ dataChunks: [Data],
        to peripheral: CBPeripheral,
        using characteristic: CBCharacteristic
    ) async {
        for chunk in dataChunks {
            peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
            GWReportManager.shared.reportEvent(
                .writtenFw(chunk.count, peripheral.identifier.uuidString)
            )
            await waitForAck()
        }
    }

    private func splitIntoChunks(_ fullData: Data) -> [Data] {
        var chunks: [Data] = []
        var index = 0
        let dataLen = fullData.count
        while index < dataLen {
            let end = index + chunkSize
            let chunk = fullData.subdata(in: index ..< min(end, dataLen))
            chunks.append(chunk)
            index += chunkSize
        }

        return chunks
    }

    private func waitForAck() async {
        await withCheckedContinuation { ackContinuation in
            self.ackContinuation = ackContinuation
        }
    }
}
