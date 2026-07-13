// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "AltMissionControl",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "AltMissionControl",
      targets: ["AltMissionControl"]
    )
  ],
  targets: [
    .executableTarget(
      name: "AltMissionControl"
    ),
    .testTarget(
      name: "AltMissionControlTests",
      dependencies: ["AltMissionControl"]
    ),
  ]
)
