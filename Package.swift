// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "FridayMac",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "FridayMac", targets: ["FridayMac"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0")
  ],
  targets: [
    .executableTarget(
      name: "FridayMac",
      path: "Sources/FridayMac"
    ),
    .testTarget(
      name: "FridayMacTests",
      dependencies: [
        "FridayMac",
        .product(name: "Testing", package: "swift-testing")
      ],
      path: "Tests/FridayMacTests"
    )
  ]
)
