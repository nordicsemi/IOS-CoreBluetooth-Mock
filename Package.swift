// swift-tools-version:5.9
//
// The `swift-tools-version` declares the minimum version of Swift required to
// build this package. Do not remove it.

import PackageDescription

let package = Package(
  name: "CoreBluetoothMock",
  platforms: [
    .macOS(.v10_14),
    .iOS(.v12),
    .watchOS(.v9),
    .tvOS(.v12)
  ],
  products: [
    .library(name: "CoreBluetoothMock", targets: ["CoreBluetoothMock"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0")
  ],
  targets: [
    .target(
      name: "CoreBluetoothMock",
      path: "CoreBluetoothMock/"
    )
  ],  
  swiftLanguageVersions: [.v5]
)
