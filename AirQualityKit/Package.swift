// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AirQualityKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "AirQualityKit", targets: ["AirQualityKit"])
    ],
    targets: [
        .target(name: "AirQualityKit"),
        .testTarget(name: "AirQualityKitTests", dependencies: ["AirQualityKit"])
    ]
)
