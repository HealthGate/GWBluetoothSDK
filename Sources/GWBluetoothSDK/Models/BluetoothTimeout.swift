//
//  BluetoothTimeout.swift
//  GWBluetoothSDK
//
//  Created by Eduardo Raupp Peretto on 25/07/24.
//

import Foundation
import Combine

class BluetoothTimeout {
    static var secondsToTimeout: TimeInterval = 180.0
    private var onTimeout: () -> Void
    private var timeoutCancellable: AnyCancellable?

    init(onTimeout: @escaping () -> Void) {
        self.onTimeout = onTimeout
    }

    func start() {
        startTimeoutTimer()
    }

    func stop() {
        timeoutCancellable?.cancel()
        timeoutCancellable = nil
    }

    func resetTimeoutTimer() {
        startTimeoutTimer()
    }

    private func startTimeoutTimer() {
        timeoutCancellable?.cancel()

        timeoutCancellable = Timer.publish(every: BluetoothTimeout.secondsToTimeout, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handleTimeout()
            }
    }

    private func handleTimeout() {
        onTimeout()
        stop()
    }

    deinit {
        stop()
    }
}
