// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "AMC",
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
      path: "Sources/AMC"
    ),
    .testTarget(
      name: "AMCTests",
      dependencies: ["AMC"],
      path: "Tests/AMCTests"
    ),
  ]
)
