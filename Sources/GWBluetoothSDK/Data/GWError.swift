//
//  GWError.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 08/03/24.
//

import Foundation

public enum GWError: Error {
    case btNotAuthorized
    case deviceNotConnected
    case btUnavailable
    case deviceNotFound
    case cannotConvertSerialToData
    case httpStatusOtherThan2xx
    case invalidAppKey
    case receivedUnformattedACK
    case failedToSendMsgsToAPI(String)
    case failedToWrite(String)
    case failure(String)

    var description: String {
        switch self {
        case let .failure(description):
            return "GWError Failure: \(description)"
        case let .failedToSendMsgsToAPI(description):
            return "Failed To Send Msgs To API: \(description)"
        case let .failedToWrite(description):
            return "Failed to write on chr: \(description)"
        default:
            return String(describing: self)
        }
    }
}
