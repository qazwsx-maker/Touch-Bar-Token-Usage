// swift-tools-version:5.9
import PackageDescription

#if os(macOS)
// Full app: AppKit UI + private Touch Bar bridge + pure-Foundation core.
let package = Package(
    name: "TouchBarTokenUsage",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "TouchBarTokenUsage", targets: ["TouchBarTokenUsage"])
    ],
    targets: [
        .target(name: "TBTCore"),
        .target(name: "TBPrivate", publicHeadersPath: "include"),
        .executableTarget(
            name: "TouchBarTokenUsage",
            dependencies: ["TBTCore", "TBPrivate"]
        ),
        .testTarget(name: "TBTCoreTests", dependencies: ["TBTCore"]),
    ]
)
#else
// On non-macOS hosts only the pure-Foundation core and its tests build,
// which lets CI (or Linux dev boxes) validate the parsing/pricing logic.
let package = Package(
    name: "TouchBarTokenUsage",
    targets: [
        .target(name: "TBTCore"),
        .testTarget(name: "TBTCoreTests", dependencies: ["TBTCore"]),
    ]
)
#endif
