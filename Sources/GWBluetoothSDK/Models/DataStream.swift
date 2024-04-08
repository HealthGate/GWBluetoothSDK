//
//  DataStream.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 08/03/24.
//

import Combine
import Foundation

public class DataStream<T: Any> {
    var onEmit: ((T) -> Void)?

    private var cancellable: AnyCancellable?
    private var stream: PassthroughSubject<T, Never>

    private var buffer: [T] = []
    private var didStartCollecting = false

    // MARK: - Init

    internal init() {
        stream = .init()
    }

    // MARK: - Methods

    func emit(_ data: T) {
        onEmit?(data)
        if didStartCollecting {
            stream.send(data)
        } else {
            buffer.append(data)
        }
    }

    public func collect(_ receiveValue: @escaping (T) -> Void) {
        cancellable = stream.receive(on: DispatchQueue.main).sink(receiveValue: receiveValue)
        sendFromBuffer()
    }

    func reset() {
        buffer = []
        cancellable = nil
        didStartCollecting = false
    }

    private func sendFromBuffer() {
        didStartCollecting = true
        for data in buffer {
            emit(data)
        }
        buffer = []
    }
}
