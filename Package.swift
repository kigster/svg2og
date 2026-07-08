// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "svg-to-omnigraffle",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SVGToOmniGraffleKit"),
        .executableTarget(
            name: "svg2og",
            dependencies: ["SVGToOmniGraffleKit"]
        ),
        .testTarget(
            name: "SVGToOmniGraffleKitTests",
            dependencies: ["SVGToOmniGraffleKit"]
        ),
    ]
)
