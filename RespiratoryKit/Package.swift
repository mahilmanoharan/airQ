// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RespiratoryKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "RespiratoryKit", targets: ["RespiratoryKit"])
    ],
    targets: [
        .target(name: "RespiratoryKit"),
        .testTarget(name: "RespiratoryKitTests", dependencies: ["RespiratoryKit"],
                    resources: [.copy("Fixtures/SchemaV2Store")])
    ]
)
