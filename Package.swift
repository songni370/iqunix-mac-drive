// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MQ80Studio",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MQ80Core", targets: ["MQ80Core"]),
        .executable(name: "iqunixctl", targets: ["mq80ctl"]),
        .executable(name: "IQUNIX-DRIVE", targets: ["MQ80Studio"]),
    ],
    targets: [
        .target(
            name: "MQ80Core",
            path: "Sources/MQ80Core"
        ),
        .executableTarget(
            name: "mq80ctl",
            dependencies: ["MQ80Core"],
            path: "Sources/mq80ctl"
        ),
        .executableTarget(
            name: "MQ80Studio",
            dependencies: ["MQ80Core"],
            path: "Sources/MQ80Studio"
        ),
    ]
)
