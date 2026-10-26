// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TwelveStepKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TwelveStepKit", targets: ["TwelveStepKit"]),
        .executable(name: "twelvestep-probe", targets: ["twelvestep-probe"]),
    ],
    targets: [
        .target(name: "TwelveStepKit", resources: [.copy("Resources/FactoryPresets")]),
        // macOS-only command-line probe using the same transport and protocol code as the iOS app.
        .executableTarget(name: "twelvestep-probe", dependencies: ["TwelveStepKit"]),
        .testTarget(name: "TwelveStepKitTests", dependencies: ["TwelveStepKit"], exclude: ["Golden"]),
    ]
)
