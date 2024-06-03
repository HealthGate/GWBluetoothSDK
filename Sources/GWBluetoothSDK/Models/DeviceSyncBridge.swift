//
//  DeviceSyncBridge.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 23/03/24.
//

import CoreBluetooth

final class DeviceSyncBridge {
    private let sendMsgsTimeInSeconds = 10

    var onAckReceived: ((Data) -> Void)?

    private let service: ServiceProtocol
    private var msgBuffer = DataBuffer()
    private var sendMsgsTask: Task<Void, Never>?


    init(service: ServiceProtocol = Service.shared) {
        self.service = service

        setupSendMsgs()
    }

    private func setupSendMsgs() {
        Task {
            sendMsgsTask = Task {
                while true {
                    if #available(iOS 16.0, *) {
                        try? await Task.sleep(for: .seconds(sendMsgsTimeInSeconds))
                    } else {
                        try? await Task.sleep(nanoseconds: UInt64(sendMsgsTimeInSeconds*1000000000))
                    }
                    await sendAllMsgs()
                }
            }
        }
    }

    func handleMsg(_ data: Data) async {
        if !data.isEmpty {
            await msgBuffer.append(data)
        }
    }

    func sendAllMsgs() async {
        guard await msgBuffer.count > 1 else { return }
        let msgs = await msgBuffer.fetchAndClear()
        guard let joinedMsg = joinDataArray(msgs, withSeparator: "&==&") else {
            GWReportManager.shared.reportEvent(.gwError(.failure("Could not join messages")))
            return
        }

        do {
            let response = try await service.sendDeviceMsgs(joinedMsg)
            onAckReceived?(response)
        } catch {
            GWReportManager.shared.reportEvent(
                .gwError(.failedToSendMsgsToAPI(error.localizedDescription))
            )
        }
    }

    func joinDataArray(_ dataArray: [Data], withSeparator separator: String) -> Data? {
        guard let separatorData = separator.data(using: .utf8) else {
            return nil
        }

        // Initialize an empty mutable Data object to accumulate the results
        var resultData = Data()

        for (index, data) in dataArray.enumerated() {
            // Append data
            resultData.append(data)

            // Append separator Data if this is not the last item
            if index < dataArray.count - 1 {
                resultData.append(separatorData)
            }
        }

        return resultData
    }

    func handledataParsedV2(_ data: Data) async {}
}

actor DataBuffer {
    private var buffer: [Data] = []

    var count: Int {
        buffer.count
    }

    func append(_ data: Data) {
        buffer.append(data)
    }

    func fetchAndClear() -> [Data] {
        let currentBuffer = buffer
        buffer.removeAll()
        return currentBuffer
    }
}
