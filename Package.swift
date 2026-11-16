// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Jarvis",
  platforms: [.macOS(.v15)],
  targets: [
    .target(name: "JarvisCore"),
    .executableTarget(
      name: "Jarvis",
      dependencies: ["JarvisCore"],
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(name: "JarvisCoreTests", dependencies: ["JarvisCore"]),
  ]
)
