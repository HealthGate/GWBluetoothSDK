//
//  GWEnv.swift
//  GWBluetoothSDK
//
//  Created by Eduardo Raupp Peretto on 08/04/24.
//

import Foundation

struct GWEnv: Codable {
    let appKey: String
    let defaultDMS: String
    let defaultBtAPI: String
    let gistDMS: String
    let gistServer: String
    let gwServerUUID: String

    static func build(fromEncodedString encodedKey: String) throws -> GWEnv {
        guard let jsonData = Data(base64Encoded: encodedKey) else {
            throw GWError.invalidAppKey
        }

        let decoder = JSONDecoder()
        let decodedEnv: GWEnv
        do {
            decodedEnv = try decoder.decode(GWEnv.self, from: jsonData)
        } catch {
            throw GWError.invalidAppKey
        }

        guard 
            !decodedEnv.appKey.isEmpty,
            decodedEnv.defaultDMS.contains("http"),
            decodedEnv.defaultBtAPI.contains("http"),
            decodedEnv.gistDMS.contains("http"),
            decodedEnv.gistServer.contains("http"),
            decodedEnv.gwServerUUID.count > 30
        else {
            throw GWError.invalidAppKey
        }

        return decodedEnv
    }
}
