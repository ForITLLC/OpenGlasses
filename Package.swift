// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenGlasses",
    platforms: [
        .iOS(.v18)
    ],
    dependencies: [
        // Meta Wearables Device Access Toolkit
        .package(url: "https://github.com/facebook/meta-wearables-dat-ios.git", exact: "0.5.0"),
        // ForIT Sign-in and Send feedback (private: needs read access to ForITLLC/for-iCommon)
        .package(url: "https://github.com/ForITLLC/for-iCommon.git", exact: "0.31.7"),
    ],
    targets: [
        .target(
            name: "OpenGlasses",
            dependencies: [
                .product(name: "MWDATCore", package: "meta-wearables-dat-ios"),
                .product(name: "MWDATCamera", package: "meta-wearables-dat-ios"),
                .product(name: "ForITCommon", package: "for-iCommon"),
            ],
            path: "OpenGlasses/Sources",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
