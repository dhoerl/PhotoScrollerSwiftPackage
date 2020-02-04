// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    //exclude: ["PhotoScrollerNetworkTest"],
    name: "PhotoScrollerSwiftPackage",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "PhotoScrollerSwiftPackage",
            targets: ["PhotoScrollerSwiftPackage"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "PhotoScrollerSwiftPackage",
            dependencies: [],
            exclude: [
                "PhotoScrollerNetworkTest",
                // These are all links solely to make development easier
                "ImageDecoding/TiledImageBuilder.h",
                "ImageDecoding/TiledImageBuilder+Draw.h",
                "ImageDecoding/TiledImageBuilder+JPEG.h",
                "ImageDecoding/TiledImageBuilder+Tile.h",
                "UI/TilingView.h",
                "UI/ImageScrollView.h",
            ]
        )
            //,
//        .testTarget(
//            name: "PhotoScrollerSwiftPackageTests",
//            dependencies: ["PhotoScrollerSwiftPackage"]),
    ]
)

/*
 targets: {
     var targets: [Target] = [
         .testTarget(
             name: "QuickTests",
             dependencies: [ "Quick", "Nimble" ],
             exclude: [
                 "QuickAfterSuiteTests/AfterSuiteTests+ObjC.m",
                 "QuickFocusedTests/FocusedTests+ObjC.m",
                 "QuickTests/FunctionalTests/ObjC",
                 "QuickTests/Helpers/QCKSpecRunner.h",
                 "QuickTests/Helpers/QCKSpecRunner.m",
                 "QuickTests/Helpers/QuickTestsBridgingHeader.h",
                 "QuickTests/QuickConfigurationTests.m",
             ]
         ),
     ]
 */
