// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Lookbook",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lookbook",
            path: "Lookbook",
            exclude: ["Lookbook.entitlements"],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("AppKit"),
            ]
        )
    ]
)
