//
//  Service.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 17/03/24.
//

import Foundation

final class Service: ServiceProtocol {
    private var dynamicBaseURL: String?

    private var dynamicServerURL: String?

    private var debugMode = false

    private var baseUrl: String {
        dynamicBaseURL ?? (GWBluetooth.shared.env?.defaultDMS ?? "")
    }

    private var btSyncUrl: String {
        dynamicServerURL ?? (GWBluetooth.shared.env?.defaultBtAPI ?? "")
    }

    // MARK: - Init (Singleton)

    static let shared: Service = .init()

    private init() {}

    // MARK: - Internal methods

    func setDebug(_ newValue: Bool) {
        debugMode = newValue
    }

    func sendReport(_ events: [GWEventData]) async throws {
        let endpoint = "btreport"
        let urlString = "\(baseUrl)\(endpoint)"
        do {
            let requestData = try serializeToJsonData(events)
            let request = try createRequest(url: urlString, body: requestData, method: "POST")
            let _ = try await makeRequest(request)
        } catch {
            log("Error sending report: \(error)")
            Task {
                await updateApiUrls()
            }
            throw error
        }
    }

    func sendDeviceMsgs(_ data: Data) async throws -> Data {
        let urlString = btSyncUrl
        let request = try createRequest(url: urlString, body: data, method: "POST")
        let (data, response) = try await makeRequest(request)
        if response.isSuccess {
            return try extractACKData(from: data)
        } else {
            Task {
                await updateApiUrls()
            }
            throw GWError.httpStatusOtherThan2xx
        }
    }

    func getFW(url: String) async throws -> Data {
        do {
            let request = try createRequest(url: url, method: "GET")
            let (data, response) = try await makeRequest(request)
            if response.isSuccess {
                return data
            } else {
                throw GWError.httpStatusOtherThan2xx
            }
        } catch {
            log("Error sending FW: \(error)")
            GWReportManager.shared.reportEvent(.gwError(.failure(error.localizedDescription)))
            throw error
        }
    }

    func updateApiUrls() async {
        do {
            dynamicBaseURL = try await getURLFromGist(GWBluetooth.shared.env?.gistDMS)
            GWReportManager.shared.reportEvent(.baseUrlUpdated(dynamicBaseURL ?? ""))
            dynamicServerURL = try await getURLFromGist(GWBluetooth.shared.env?.gistServer)
            GWReportManager.shared.reportEvent(.baseUrlUpdated(dynamicBaseURL ?? ""))
        } catch {
            GWReportManager.shared.reportEvent(
                .gwError(.failure(error.localizedDescription))
            )
        }
    }

    // MARK: - Private methods

    private func extractACKData(from responseData: Data) throws -> Data {
        // Attempt to decode the JSON data to a dictionary
        guard let jsonDict = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: String],
              let ackBase64String = jsonDict["ACK"]
        else {
            throw GWError.receivedUnformattedACK
        }
        guard let ackData = Data(base64Encoded: ackBase64String) else {
            throw GWError.receivedUnformattedACK
        }
        return ackData
    }

    private func log(_ str: String) {
        if debugMode {
            print(str)
        }
    }

    private func getURLFromGist(_ url: String?) async throws -> String {
        guard let url else { throw GWError.invalidAppKey }
        let request = try createRequest(url: url, withDeviceHeaders: false)
        let (data, response) = try await makeRequest(request)
        guard response.isSuccess else {
            throw GWError.httpStatusOtherThan2xx
        }
        guard
            let urlFromGist = String(data: data, encoding: .utf8),
            urlFromGist.hasPrefix("http")
        else {
            throw URLError(.cannotParseResponse)
        }
        return urlFromGist
    }

    private func makeRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        log("Request URL: \(request.url?.absoluteString ?? "Bad URL")")

        if let httpHeaders = request.allHTTPHeaderFields {
            log("Request Header:")
            for (key, value) in httpHeaders {
                log("\(key): \(value)")
            }
        }

        if let body = request.httpBody {
            log("Request Body (Base64): \(body.base64EncodedString())")
        }

        log("Starting Request...")
        let (data, response) = try await URLSession.shared.data(for: request)
        log("Response Status Code: \(response.httpCode?.description ?? "Unknown")")
        log("Response: \(String(data: data, encoding: .utf8) ?? "")")

        return (data, response)
    }

    private func serializeToJsonData<T: Encodable>(_ object: T) throws -> Data {
        do {
            let jsonData = try JSONEncoder().encode(object)
            return jsonData
        } catch {
            log("Error serializing object to JSON: \(error)")
            throw error
        }
    }

    private func createRequest(url _url: String, body: Data? = nil, method: String = "GET", withDeviceHeaders: Bool = true) throws -> URLRequest {
        guard let url = URL(string: _url) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method

        if withDeviceHeaders {
            guard
                let appKey = GWBluetooth.shared.env?.appKey,
                appKey.count > 30
            else {
                throw GWError.invalidAppKey
            }
            request.addValue(GWReportManager.shared.clientSerial, forHTTPHeaderField: "serial")
            request.addValue(GWReportManager.shared.btId, forHTTPHeaderField: "btid")
            request.addValue(appKey, forHTTPHeaderField: "X-API-Key")
            request.addValue(Utils.deviceId, forHTTPHeaderField: "device")
        }

        if let body {
            request.httpBody = body
        }
        return request
    }
}

extension URLResponse {
    var httpCode: Int? {
        guard let httpResponse = self as? HTTPURLResponse else {
            return nil
        }
        return httpResponse.statusCode
    }

    var isSuccess: Bool {
        guard let httpCode else { return false }
        return httpCode >= 200 && httpCode < 300
    }
}

extension Data {
    static func fromInt(_ value: Int) -> Data {
        var intVal = value
        return Data(bytes: &intVal, count: MemoryLayout<Int>.size)
    }

    static func fromString(_ value: String) throws -> Data {
        guard let data = value.data(using: .utf8) else {
            throw GWError.cannotConvertSerialToData
        }
        return data
    }
}
