// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "AMC",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "AMC",
      targets: ["AMC"]
    )
  ],
  targets: [
    .executableTarget(
      name: "AMC",
      path: "Sources/AMC",
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "AMCTests",
      dependencies: ["AMC"],
      path: "Tests/AMCTests"
    ),
  ]
)
