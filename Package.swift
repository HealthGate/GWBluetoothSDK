// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "GWBluetoothSDK",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(name: "GWBluetoothSDK", targets: ["GWBluetoothSDK"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "GWBluetoothSDK",
            dependencies: []
        ),
    ]
)
