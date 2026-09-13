// swift-tools-version: 6.0
// ⚠️ 下方 binaryTarget 里的 url 与 checksum 两行由 scripts/release.sh 自动替换。
//    两者必须各占一行、值用双引号包裹、且缩进对齐；
//    改成多行拼接或换单引号会导致替换失败
//    （脚本有 grep 复验，会中止而非发出坏包）。

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
            url: "https://github.com/weaver-max/gemstone-swift/releases/download/0.0.1-test2/GemstoneFFI.xcframework.zip",
            checksum: "b57517e6a37d5b74fe5c13de7cf66d36270a01fe469445fa2233a0d2a54a7776"
        ),
    ]
)
