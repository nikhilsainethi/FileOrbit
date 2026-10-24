// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FileOrbit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "FileOrbitCore", targets: ["FileOrbitCore"]), .executable(name: "FileOrbit", targets: ["FileOrbit"]), .executable(name: "fileorbit-cli", targets: ["FileOrbitCLI"])],
    targets: [
        .target(name: "FileOrbitCore"),
        .executableTarget(name: "FileOrbit", dependencies: ["FileOrbitCore"]),
        .executableTarget(name: "FileOrbitCLI", dependencies: ["FileOrbitCore"]),
        .testTarget(name: "FileOrbitCoreTests", dependencies: ["FileOrbitCore"]),
        .testTarget(name: "FileOrbitAppTests", dependencies: ["FileOrbit", "FileOrbitCore"])
    ],
    swiftLanguageModes: [.v5]
)
