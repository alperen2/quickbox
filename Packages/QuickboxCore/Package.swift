// swift-tools-version: 6.0
import PackageDescription

// Platform-independent quickbox logic: the Markdown task line format, draft analysis and
// natural-language dates. Shared by the macOS app and future iOS/cloud clients, so it must
// stay free of UI, file-system and app-specific dependencies.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("BareSlashRegexLiterals"),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "QuickboxCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "QuickboxCore", targets: ["QuickboxCore"])
    ],
    targets: [
        .target(name: "QuickboxCore", swiftSettings: swiftSettings),
        .testTarget(name: "QuickboxCoreTests", dependencies: ["QuickboxCore"], swiftSettings: swiftSettings)
    ],
    // Matches the app targets. Swift 6 mode needs the static `Regex` patterns
    // (not `Sendable`) reworked first.
    swiftLanguageModes: [.v5]
)
