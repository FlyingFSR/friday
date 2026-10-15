// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "FridayMac",
  // mlx-swift requires macOS 14.
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "FridayMac", targets: ["FridayMac"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0"),
    // Pinned exactly: the Metal shader library shipped next to the binary
    // (scripts/fetch-mlx-metallib.sh) must match this release's MLX core (0.32.2).
    .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.32.3")
  ],
  targets: [
    .executableTarget(
      name: "FridayMac",
      dependencies: ["Qwen3ASR"],
      path: "Sources/FridayMac"
    ),
    // On-device Qwen3-ASR inference, ported from soniqo/speech-swift (Apache 2.0).
    // See Sources/Qwen3ASR/NOTICE.md.
    .target(
      name: "Qwen3ASR",
      dependencies: [
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXNN", package: "mlx-swift")
      ],
      path: "Sources/Qwen3ASR",
      exclude: ["NOTICE.md", "LICENSE-Apache-2.0"]
    ),
    .testTarget(
      name: "FridayMacTests",
      dependencies: [
        "FridayMac",
        "Qwen3ASR",
        .product(name: "Testing", package: "swift-testing")
      ],
      path: "Tests/FridayMacTests"
    )
  ]
)
