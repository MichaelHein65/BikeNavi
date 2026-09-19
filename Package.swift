// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BikeNaviCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "BikeNaviCore", targets: ["BikeNaviCore"])],
    targets: [
        .target(name: "BikeNaviCore", path: "ios/BikeNavi/Core", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "BikeNaviCoreTests", dependencies: ["BikeNaviCore"], path: "tests/Swift")
    ]
)
