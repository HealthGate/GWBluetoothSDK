//
//  Utils.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 24/03/24.
//

import UIKit

enum Utils {
    static var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"
    }
}
