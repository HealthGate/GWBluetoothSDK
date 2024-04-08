//
//  ServiceProtocol.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 17/03/24.
//

import Foundation

protocol ServiceProtocol {
    func sendReport(_ events: [GWEventData]) async throws
    func sendDeviceMsgs(_ data: Data) async throws -> Data
    func getFW(url: String) async throws -> Data
}
