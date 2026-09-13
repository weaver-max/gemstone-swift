// swift-tools-version: 6.0
// ⚠️ 本文件的 url 与 checksum 两行由 scripts/release.sh 自动替换。
//    格式必须保持 `url: "..."` 和 `checksum: "..."` 各占一行、双引号，
//    改成多行拼接或换引号会导致 sed 替换失败（脚本有 grep 复验，会中止而非发坏包）。

import PackageDescription

let package = Package(
    name: "Gemstone",
    platforms: [
        .iOS(.v17),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "Gemstone",
            targets: ["Gemstone"]
        ),
    ],
    targets: [
        // Swift 绑定层：UniFFI 生成，由 release.sh 全量覆盖
        .target(
            name: "Gemstone",
            dependencies: ["GemstoneFFI"],
            swiftSettings: [
                // TODO: GemstoneFFI 完整支持 Swift 6 后移除
                .swiftLanguageMode(.v5),
            ]
        ),
        // C 层 + 静态库：由 XCFramework 提供，不在本仓库源码中
        .binaryTarget(
            name: "GemstoneFFI",
            url: "https://github.com/YOUR-ORG/gemstone-swift/releases/download/0.0.0/GemstoneFFI.xcframework.zip",
            checksum: "0000000000000000000000000000000000000000000000000000000000000000"
        ),
    ]
)
