// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppleShared",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AppleShared", targets: ["AppleShared"]),
    ],
    dependencies: [.package(path: "../native-archive")],
    targets: [
        .systemLibrary(name: "CZlib"),
        .target(name: "CComicArchive", dependencies: [
            .product(name: "XLibArchiveCore", package: "native-archive"),
            .product(name: "XLibUnRAR", package: "native-archive")]),
        .target(name: "AppleShared", dependencies: ["CZlib", "CComicArchive"], resources: [.process("Resources")]),
        .testTarget(name: "AppleSharedTests", dependencies: ["AppleShared"]),
    ]
)
