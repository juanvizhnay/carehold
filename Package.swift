// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CareHold",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "CareHold",
            targets: ["CareHold"]
        ),
    ],
    dependencies: [
        .package(path: "Packages/Core"),
        .package(url: "https://github.com/supabase/supabase-swift", exact: "2.55.4"),
    ],
    targets: [
        // App: composition root plus the patient and clinician screens.
        // Screens talk to `CareRepository` from Core; only the composition root knows `Data`.
        .target(
            name: "CareHold",
            dependencies: [
                .product(name: "Core", package: "Core"),
                "DesignSystem",
                "Data",
            ]
        ),
        .target(
            name: "DesignSystem",
            dependencies: [
                .product(name: "Core", package: "Core"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "Data",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "Supabase", package: "supabase-swift"),
            ]
        ),
    ]
)
