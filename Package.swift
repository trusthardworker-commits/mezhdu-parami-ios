// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScheduleCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "ScheduleCore", targets: ["ScheduleCore"])],
    targets: [
        .target(name: "ScheduleCore", path: "Shared", exclude: ["PrivacyInfo.xcprivacy"]),
        .testTarget(name: "ScheduleCoreTests", dependencies: ["ScheduleCore"], path: "Tests")
    ]
)
