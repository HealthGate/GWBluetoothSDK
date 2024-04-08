//
//  GWServiceCharacteristic.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 08/03/24.
//

import Foundation

enum GWServiceCharacteristic: String {
    case statusAck = "33333333-2222-2222-1111-1111FFFFFFFF"
    case dataRaw = "35333333-2222-2222-1111-1111FFFFFFFF"
    case dataParsed = "36333333-2222-2222-1111-1111FFFFFFFF"
    case dataParsedV2 = "37333333-2222-2222-1111-1111FFFFFFFF"
    case logPrint = "38333333-2222-2222-1111-1111FFFFFFFF"
    case logPacket = "39333333-2222-2222-1111-1111FFFFFFFF"
    case serialFw = "40333333-2222-2222-1111-1111FFFFFFFF"
}
