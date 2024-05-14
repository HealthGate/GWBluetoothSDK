//
//  GWBluetooth.swift
//  GWIntegrationSample
//
//  Created by Eduardo Raupp Peretto on 08/03/24.
//

import Combine

public class GWBluetooth {
    // MARK: - Public Properties

    public var debugMode = false {
        didSet {
            print("Debug mode: \(debugMode)")
            GWReportManager.shared.setDebug(debugMode)
            Service.shared.setDebug(debugMode)
            btManager.setDebug(debugMode)
        }
    }

    private(set) var env: GWEnv?

    // MARK: - Private Properties

    private let btManager: BluetoothManager
    private var isConnectedCancellable: AnyCancellable?

    // MARK: - Init (Singleton)

    public static let shared: GWBluetooth = .init()

    private init() {
        btManager = BluetoothManager()
    }

    // MARK: - Public methods

    /// Realiza o setup do SDK e Bluetooth, e inicializa a busca por dispositivos GoldWing próximos. Uma vez que um dispositivo é conectado, toda a troca de informações passa a acontecer em background, e não é necessária nenhuma ação por parte do app.
    ///
    /// - appKey: Chave de integração disponibilizada pela HealthGate
    public func start(appKey: String) throws {
        env = try .build(fromEncodedString: appKey)
        
        Task {
            await Service.shared.updateApiUrls()
        }

        btManager.startConnectionLoop()
    }

    /// Desconecta a atual conexão Bluetooth com o GoldWing, caso ativa, e interrompe todo o processamento e busca por dispositivos próximos.
    public func stop() {
        btManager.stop()
    }

    /// Retorna uma stream de eventos assíncronos referente ao Status da conexão Bluetooth.
    /// - Para escutar os eventos emitidos, basta utilizar a função `collect`. Exemplo:
    /// ```
    /// statusStream.collect { [weak self] newStatus in
    ///     self?.handleStatus(newStatus)
    /// }
    /// ```
    /// - Veja o Enum `GWStatus` para visualizar todos os eventos possíveis.
    public func getStatusStream() -> DataStream<GWStatus> {
        btManager.statusStream
    }

    /// Retorna uma stream de eventos assíncronos referente ao Status da conexão Bluetooth.
    /// - Para escutar os eventos emitidos, basta utilizar a função `collect`. Exemplo:
    /// ```
    /// isConnectedStream.collect { [weak self] newValue in
    ///     self?.isConnected = newValue
    /// }
    /// ```
    public func getIsConnectedStream() -> DataStream<Bool> {
        let isConnectedStream = DataStream<Bool>()

        isConnectedCancellable = btManager.$isConnected.sink { newValue in
            isConnectedStream.emit(newValue)
        }

        isConnectedStream.emit(btManager.isConnected)

        return isConnectedStream
    }
}
