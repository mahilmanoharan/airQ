// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AirQualityKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "AirQualityKit", targets: ["AirQualityKit"])
    ],
    targets: [
        .target(name: "AirQualityKit"),
        .testTarget(name: "AirQualityKitTests", dependencies: ["AirQualityKit"])
    ]
)
