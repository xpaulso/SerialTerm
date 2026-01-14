// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SerialTerm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "SerialTerm",
            targets: ["SerialTerm"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SerialTerm",
            dependencies: [],
            path: "SerialTerm",
            exclude: [
                "Resources/Info.plist"
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "SerialTermTests",
            dependencies: ["SerialTerm"],
            path: "Tests"
        )
    ]
)
