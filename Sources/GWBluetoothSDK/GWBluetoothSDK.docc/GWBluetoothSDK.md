# ``GWBluetoothSDK``

Framework para conexão de dispositivos iOS com os dispositivos GoldWing®

## Overview

Através desse framework, uma conexão bluetooth é estabelecida entre o dispositivo iOS e o GoldWing®. 
Uma vez que a conexão é estabelecida, GoldWing® fará uma ponte de dados criptografados, encaminhando mensagens ao servidor HealthGate, e devolvendo informações ao GoldWing®.
Além disso, o framework grava um histórico de eventos unicamente no escopo de conexão Bluetooth, reportando aos servidores HealthGate, para questão de telemetria.
Todas as mensagens recebidas do GoldWing® são criptografadas.

## Utilização

O framework disponibiliza uma única classe pública: `GWBluetooth`. Trata-se de um singleton. Logo, para instanciá-la:
```let gwBluetooth = GWBluetooth.shared```

A partir da classe `GWBluetooth`, são disponibilizadas apenas 4 funções para utilização do aplicativo:

- ```public func startConnection(appKey: String)```
Realiza o setup do Bluetooth, e inicializa a busca por dispositivos GoldWing próximos. Uma vez que um dispositivo é conectado, toda a troca de informações passa a acontecer em background, e não é necessária nenhuma ação por parte do app.

- appKey: Chave de integração disponibilizada pela HealthGate

#### Funções Auxiliares (não obrigatórias)

- ```public func stop()```
Desconecta a atual conexão Bluetooth com o GoldWing, caso ativa, e interrompe todo o processamento e busca por dispositivos próximos.

- ```public func getStatusStream() -> DataStream<GWStatus>```
Retorna uma stream de eventos assíncronos referente ao Status da conexão Bluetooth.
Para escutar os eventos emitidos, basta utilizar a função `collect`. Exemplo:
```
isConnectedStream.collect { [weak self] newValue in
    self?.isConnected = newValue
}
```

- ```public func getIsConnectedStream() -> DataStream<Bool>```
Retorna uma stream de eventos assíncronos referente ao Status da conexão Bluetooth.
- Para escutar os eventos emitidos, basta utilizar a função `collect`. Exemplo:
```
isConnectedStream.collect { [weak self] newValue in
    self?.isConnected = newValue
}
```

## Modo debug
A classe `GWBluetooth` disponibiliza uma variável pública `debugMode`. Caso seja ativada, todos os eventos, reports e requisições serão escritas no terminal (`prints`).

Atenção! NÃO utilize `debugMode = true` em produção.
