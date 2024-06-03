//
//  FirmwareUpdater.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 07/04/24.
//

import CoreBluetooth
import Foundation

final class FirmwareUpdater {
    private let chunkSize = 500
    private let service: ServiceProtocol
    private var characteristic: CBCharacteristic?
    private var ackContinuation: CheckedContinuation<Void, Never>?
    private var currentTask: Task<Void, Never>?
    private let stateQueue = DispatchQueue(label: "com.firmwareupdater.stateQueue", attributes: .concurrent)
    private var isAwaitingAck = false

    init(service: ServiceProtocol = Service.shared) {
        self.service = service
    }

    func hasUpdateInProgress() -> Bool {
        currentTask != nil
    }

    func startUpdate(
        _ peripheral: CBPeripheral,
        to fwUrl: String,
        using characteristic: CBCharacteristic
    ) {
        currentTask = Task {
            do {
                let fwData = try await service.getFW(url: fwUrl)
                let dataChunks = splitIntoChunks(fwData)
                self.characteristic = characteristic
                await sendDataChunks(dataChunks, to: peripheral, using: characteristic)
            } catch {
                GWReportManager.shared.reportEvent(.gwError(.failure(error.localizedDescription)))
            }
        }
    }

    func signalAck(for characteristic: CBCharacteristic) {
        stateQueue.sync {
            guard characteristic == self.characteristic, self.isAwaitingAck else { return }
            self.isAwaitingAck = false
            ackContinuation?.resume()
        }
    }

    func cancelUpdate() {
        currentTask?.cancel()
        GWReportManager.shared.reportEvent(.gwError(.fwUpdateCanceled))
    }

    private func sendDataChunks(
        _ dataChunks: [Data],
        to peripheral: CBPeripheral,
        using characteristic: CBCharacteristic
    ) async {
        for (index, chunk) in dataChunks.enumerated() {
            do {
                if (index % 200) == 0 {
                    GWReportManager.shared.reportEvent(
                        .writtenFw(index, chunk.count, peripheral.identifier.uuidString)
                    )
                }
                stateQueue.async(flags: .barrier) { [weak self] in
                    self?.isAwaitingAck = true
                }
                peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
                try await waitForAck()
            } catch {
                GWReportManager.shared.reportEvent(.gwError(.fwAckTimeout))
                currentTask?.cancel()
                break
            }
        }
        ackContinuation = nil
        let eof = Data([0x0])
        peripheral.writeValue(eof, for: characteristic, type: .withResponse)
        GWReportManager.shared.reportEvent(.finishedFwUpdate(dataChunks.count))
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

    private func waitForAck() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { ackContinuation in
                    self.ackContinuation = ackContinuation
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 6 * 1_000_000_000)
                throw NSError(domain: "FirmwareUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for ACK"])
            }

            try await group.next()
            group.cancelAll()
        }
    }
}
