// swift-tools-version: 6.2
import CompilerPluginSupport
import PackageDescription

// Builds the example in skills/swift-best-practices/references/macros.md. CI writes each
// file of that example into Sources/ before it builds.
let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .strictMemorySafety(),
  .treatAllWarnings(as: .error),
]

let package = Package(
  name: "MyMacros",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0")
  ],
  targets: [
    .macro(
      name: "MyMacrosPlugin",
      dependencies: [
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ],
      swiftSettings: settings
    ),
    .target(name: "MyMacros", dependencies: ["MyMacrosPlugin"], swiftSettings: settings),
  ],
  swiftLanguageModes: [.v6]
)
