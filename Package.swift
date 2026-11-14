// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Zhijian",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DictionaryCore", targets: ["DictionaryCore"]),
        .executable(name: "ZhijianApp", targets: ["ZhijianApp"]),
        .executable(name: "zhijian", targets: ["ZhijianCLI"]),
        .executable(name: "DictionaryChecks", targets: ["DictionaryChecks"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "DictionaryCore", dependencies: ["CSQLite"], resources: [.process("Resources")]),
        .executableTarget(name: "ZhijianApp", dependencies: ["DictionaryCore"]),
        .executableTarget(name: "ZhijianCLI", dependencies: ["DictionaryCore"]),
        .executableTarget(name: "DictionaryChecks", dependencies: ["DictionaryCore"], path: "Tests/DictionaryCoreTests")
    ]
)
