// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RespiratoryKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "RespiratoryKit", targets: ["RespiratoryKit"])
    ],
    targets: [
        .target(name: "RespiratoryKit"),
        .testTarget(name: "RespiratoryKitTests", dependencies: ["RespiratoryKit"])
    ]
)
