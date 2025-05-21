// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SmartCalculator",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SmartCalculator",
            targets: ["SmartCalculator"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SmartCalculator",
            dependencies: [],
            path: "SmartCalculator/Sources/SmartCalculator" // Corrected path
        ),
        .testTarget(
            name: "SmartCalculatorTests",
            dependencies: ["SmartCalculator"],
            path: "SmartCalculatorTests"
        )
    ]
)
