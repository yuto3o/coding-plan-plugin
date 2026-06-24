// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodingPlanPlugin",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodingPlanPlugin", targets: ["CodingPlanPlugin"])
    ],
    targets: [
        .executableTarget(
            name: "CodingPlanPlugin",
            linkerSettings: [
                .linkedFramework("WebKit")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
