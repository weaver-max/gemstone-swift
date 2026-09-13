# Gemstone Swift

Gem Wallet Rust core（`gemstone`）的 Swift 绑定分发包。

> ⚠️ **本仓库内容全部由发布脚本自动生成，不要手动修改。**
>
> - Rust 源码在 [YOUR-ORG/core](https://github.com/YOUR-ORG/core)
> - 发布流程见 core 仓库的 `脚本发布教程.md`
> - 要改 Swift 侧行为，请改 Rust 源码后重新发版，**不要直接改这里的 `Gemstone.swift`**（下次发版会被覆盖）

---

## 安装

Swift Package Manager：

```swift
dependencies: [
    .package(url: "https://github.com/YOUR-ORG/gemstone-swift", from: "2.114.10")
]
```

Xcode：`File → Add Package Dependencies` → 填仓库地址 → 选版本。

## 使用

```swift
import Gemstone

print(libVersion())
```

更完整的接口说明见 core 仓库的《基于 gem-core 的 iOS 和安卓开发教程》与《gem 私钥管理》。

---

## 仓库结构

```
gemstone-swift/
├── Package.swift                  # 包定义（url / checksum 由脚本替换）
├── Sources/
│   └── Gemstone/
│       └── Gemstone.swift         # UniFFI 生成的绑定，每次发版全量覆盖
└── README.md
```

**二进制不在 git 里** —— `GemstoneFFI.xcframework.zip` 作为 Release 资产分发，
`Package.swift` 的 `binaryTarget` 按 URL + checksum 拉取。

## 版本对应

本仓库的版本号与 core 的 `Cargo.toml` workspace version 一一对应。

每个 tag 的 commit message 记录了对应的 core commit：

```
Release 2.114.10 (core@820c4155)
```

出问题时可据此回溯到确切的 Rust 源码版本。

## 平台要求

| 项 | 要求 |
|---|---|
| iOS | 17.0+ |
| macOS | 15.0+ |
| 架构 | arm64（真机 + 模拟器）；**不支持 Intel Mac** |

---

## 给维护者

### 本仓库必须保持 public

SPM 的 `.binaryTarget(url:checksum:)` 下载 zip 时**不带任何鉴权头**。
仓库设为 private 会导致下游拉取时 404。

若必须私有化，见 core 仓库《脚本发布教程》§2.4 的三条出路
（提交 xcframework 进仓库 + Git LFS / 改用 CocoaPods）。

### 不要手动打 tag

tag 由 `release.sh` 创建，且必须指向包含**已更新 `Package.swift`** 的那个 commit。
手动打 tag 容易造成「tag 指向旧 commit，下游拉到旧 zip URL」。
`verify-release.sh` 会检查这一项。
