// swift-tools-version:5.9
//
//  Package.swift
//  BiDiMarkdown
//
//  Created by David Noy on 07/08/2026.
//

import PackageDescription

let package = Package(
    name: "BiDiMarkdown",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .macCatalyst(.v16)
    ],
    products: [
        .library(name: "BiDiMarkdown", targets: ["BiDiMarkdown"])
    ],
    dependencies: [
        // Lets `swift package generate-documentation` build the DocC
        // catalog locally. Not required for Xcode's own Product > Build
        // Documentation, and not linked into anything that depends on this
        // package — it's a command plugin, inert unless invoked.
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0")
    ],
    targets: [
        .target(name: "BiDiMarkdown")
    ]
)
