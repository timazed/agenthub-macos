// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CEFKit",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "CEFKit",
            targets: ["CEFKit"]
        ),
    ],
    targets: [
        .target(
            name: "CCEFWrapper",
            path: "Sources/CCEFWrapper/VendorCEFRuntime/libcef_dll",
            exclude: [],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath(".."),
                .headerSearchPath("../include"),
                .headerSearchPath("../../shim_headers"),
                .headerSearchPath("."),
                .define("USING_CEF_SHARED"),
                .define("WRAPPING_CEF_SHARED"),
                .define("CEF_API_VERSION", to: "13601"),
            ],
            cxxSettings: [
                .headerSearchPath(".."),
                .headerSearchPath("../include"),
                .headerSearchPath("../../shim_headers"),
                .headerSearchPath("."),
                .define("USING_CEF_SHARED"),
                .define("WRAPPING_CEF_SHARED"),
                .define("CEF_API_VERSION", to: "13601"),
                .unsafeFlags(["-std=c++20"]),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
        .target(
            name: "CEFKitRuntime",
            path: "Sources/CEFKitRuntime"
        ),
        .target(
            name: "CEFKit",
            dependencies: ["CCEFWrapper", "CEFKitRuntime"],
            path: "Sources/CEFKit"
        ),
    ],
    cxxLanguageStandard: .cxx20
)
