//
//  GWReportManager.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 08/03/24.
//

import Foundation

class GWReportManager {
    private let sendReportTimeInSeconds = 120
    private var debugMode = false
    private var buffer = ReportBuffer()
    var service: ServiceProtocol = Service.shared
    private var sendReportTask: Task<Void, Never>?
    var btId: String = "Unknown"
    var clientSerial: String = "Unknown"

    static let shared = GWReportManager()
    private init() {
        setupEventReports()
    }

    func setupEventReports() {
        sendReportTask = Task {
            while true {
                if #available(iOS 16.0, *) {
                    try? await Task.sleep(for: .seconds(sendReportTimeInSeconds))
                } else {
                    try? await Task.sleep(nanoseconds: UInt64(sendReportTimeInSeconds * 1000000000))
                }
                guard GWBluetooth.shared.env != nil else { continue }
                await sendReports()
            }
        }
    }

    func setDebug(_ newValue: Bool) {
        debugMode = newValue
    }

    func reportEvent(_ event: GWBtEvent) {
        if debugMode {
            print(event.description)
        }
        Task {
            await buffer.append(.init(from: event))
        }
    }

    private func sendReports() async {
        let events = await buffer.fetchAndClear()
        guard !events.isEmpty else { return }
        do {
            try await service.sendReport(events)
        } catch {
            reportEvent(.gwError(.failure(error.localizedDescription)))
        }
    }
}

actor ReportBuffer {
    private var buffer: [GWEventData] = []

    func append(_ event: GWEventData) {
        buffer.append(event)
    }

    func fetchAndClear() -> [GWEventData] {
        let currentBuffer = buffer
        buffer.removeAll()
        return currentBuffer
    }
}
