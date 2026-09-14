# Gemstone Swift

Gem Wallet Rust core（`gemstone`）的 Swift 绑定分发包。

> ⚠️ **本仓库内容由发布脚本自动生成，除 `Package.swift` 结构与本文件外不要手动修改。**
>
> - Rust 源码在 [weaver-max/core](https://github.com/weaver-max/core)
> - 发布流程见 core 仓库的 `脚本发布教程.md`
> - 要改 Swift 侧行为，请改 Rust 源码后重新发版，**不要直接改 `Sources/Gemstone/Gemstone.swift`**（下次发版会被覆盖）

---

## 目录

- [下游接入](#下游接入)
- [快速上手](#快速上手)
- [仓库结构](#仓库结构)
- [版本对应](#版本对应)
- [平台要求](#平台要求)
- [故障排查](#故障排查)
- [给维护者](#给维护者)

> 📖 **完整集成指南见 [iOS-Integration-Guide.md](iOS-Integration-Guide.md)** —— 含许可证边界、
> `AlienProvider` / `GemPreferences` 两个必需实现的完整代码、Keychain 密码管理、
> 发交易全流程、API 参考、落地检查清单。
>
> 本 README 只做速查，第一次接入请读那一份。

---

## 下游接入

**不需要安装 Rust、NDK 或任何额外工具链。** SPM 会自动下载预编译的 XCFramework 并校验 checksum。

### 方式 A：Xcode 图形界面

```
File → Add Package Dependencies…
  仓库地址：https://github.com/weaver-max/gemstone-swift
  Dependency Rule：Up to Next Major Version → 2.114.10
```

### 方式 B：`Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/weaver-max/gemstone-swift", from: "2.114.10")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Gemstone", package: "gemstone-swift")
        ]
    )
]
```

---

## 快速上手

### 最小验证

接入后先跑这一行，能打印出版本号就说明整条链路通了：

```swift
import Gemstone

print(libVersion())
```

### 助记词

```swift
let mnemonic = GemMnemonic()

let words = try mnemonic.generate(wordCount: 12)   // 12 / 15 / 18 / 21 / 24
mnemonic.isValid(words: words)                      // 校验整组
mnemonic.isValidWord(word: "abandon")               // 校验单词
mnemonic.suggestWords(prefix: "ab", limit: 5)       // 输入联想
mnemonic.findInvalidWords(words: words)             // 高亮错词
```

熵源为 OS CSPRNG（`getrandom`），非用户态 PRNG。

### 创建钱包

```swift
let keystore = try GemKeystore(baseDir: keystoreURL.path)

// 导入预览：纯派生，不落盘、不需要密码
let preview = try keystore.previewImport(
    import: .multicoinPhrase(words: words, chains: ["ethereum"])
)
print(preview.accounts.map(\.address))

// 落盘
let stored = try keystore.createStore(
    import: .multicoinPhrase(words: words, chains: ["ethereum"]),
    password: passwordBytes
)
// stored.walletId    "multicoin_0x9858Ef..."
// stored.keystoreId  "f32a9e95-4904-533b-..."
// stored.accounts    [GemKeystoreAccount]
```

> 💡 **即使只做单链钱包也建议用 `.multicoinPhrase`**，不要用 `.singlePhrase`。
> multicoin 的 walletId 固定由以太坊地址派生，与启用了几条链无关；
> 用 singlePhrase 后续想加链会导致 walletId 变化 → keystoreId 变化 → **密钥文件定位不到**。

### 签名

**私钥不跨 FFI 边界。** App 只持有 `keystoreId`（一个 UUID）和密码字节，拿回签名结果：

```swift
let signed = try keystore.sign(
    keystoreId: stored.keystoreId,
    chain: "ethereum",
    input: signerInput,
    password: passwordBytes
)
```

密码字节用完立即擦除：

```swift
defer { passwordBytes.resetBytes(in: 0..<passwordBytes.count) }
```

### 链上操作

> 🔴 **需要先实现 `AlienProvider`（网络）和 `GemPreferences`（键值存储）两个协议**，
> Rust 侧不做 HTTP，由平台注入。**不实现这两个，gemstone 跑不起来。**
> 完整可用代码见 [iOS-Integration-Guide.md §5](iOS-Integration-Guide.md#5-四个核心文件)。

```swift
let gateway = GemGateway(
    provider: yourAlienProvider,
    preferences: yourPreferences,
    securePreferences: yourSecurePreferences,
    apiUrl: apiURL
)

let balance = try await gateway.getBalanceCoin(chain: "ethereum", address: address)
```

`Chain` 在 FFI 层是 **String** 而非枚举，以太坊传 `"ethereum"`（小写，无下划线）。

完整接口说明见 core 仓库的：
- 《基于 gem-core 的 iOS 和安卓开发教程》
- 《gem 私钥管理》
- 《rust 回调原生端写好的接口(功能)》

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

zip 内含两个切片：

```
GemstoneFFI.xcframework/
├── ios-arm64/              真机
└── ios-arm64-simulator/    模拟器
```

---

## 版本对应

本仓库的版本号与 core 的 `Cargo.toml` workspace version 一一对应。

每个 tag 的 commit message 记录了对应的 core commit：

```
Release 2.114.10 (core@820c4155)
```

出问题时可据此回溯到确切的 Rust 源码版本。

---

## 平台要求

| 项 | 要求 |
|---|---|
| iOS | 17.0+ |
| macOS | 15.0+ |
| 架构 | arm64（真机 + 模拟器） |
| Intel Mac | ❌ 不支持 |

---

## 故障排查

| 症状 | 原因 | 解法 |
|---|---|---|
| SPM 报 **404 / 下载失败** | 本仓库不是 public。`binaryTarget` 下载**不带鉴权头** | 见[给维护者](#本仓库必须保持-public) |
| SPM 报 **`malformedResponse("unexpected tree entry ...")`** | 仓库里混入了**非 ASCII 文件名**。git 对其做八进制转义并加引号，SPM 的 git tree 解析器处理不了 | 维护者需把文件名改成 ASCII。排查：`git ls-tree -r HEAD \| grep '"'` |
| SPM 报 **checksum mismatch** | Release 的 zip 被重新上传过，但 `Package.swift` 未同步 | 让维护者重新发一个版本 |
| 拉到的是**旧版本的绑定** | tag 指向的 commit 里 `Package.swift` 还是旧 URL | 同上；core 仓库的 `verify-release.sh` 会检出此问题 |
| 启动即崩，提示 **checksum / contract version** | 绑定与原生库版本错位（通常是有人手工拷贝过文件） | 清缓存重拉；仍不行则让维护者重发 |
| `import Gemstone` 报 **module not found** | 依赖未解析成功 | `File → Packages → Reset Package Caches` |
| 模拟器能跑、真机不能（或反之） | XCFramework 缺对应切片 | 让维护者检查发布时是否两个架构都编了 |

### 清缓存

```
Xcode → File → Packages → Reset Package Caches
```

或命令行：

```bash
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf .build .swiftpm
```

---

## 给维护者

### 日常发版：不用碰这个仓库

在 **core 仓库**执行即可，脚本会自动 clone 本仓库、覆盖绑定、替换 `Package.swift`、打 tag、建 Release：

```bash
cd path/to/core
./scripts/preflight.sh
./scripts/release.sh 2.114.11
./scripts/verify-release.sh 2.114.11
```

### 什么时候需要手动改本仓库

| 场景 | 是否手动 |
|---|---|
| 日常发版 | ❌ 脚本全自动 |
| 改 platforms（如支持 iOS 16） | ✅ 改 `Package.swift` |
| 加新的 product / target | ✅ 改 `Package.swift` |
| 更新本 README | ✅ |
| 改 Swift 侧行为 | ❌ **改 Rust 源码后重新发版** |
| 撤回发错的版本 | ❌ 跑 core 仓库的 `./scripts/rollback.sh <ver>` |

### `Package.swift` 的格式约束

`release.sh` 用 `sed` 替换 `binaryTarget` 里的两行，格式必须保持：

- `url:` 与 `checksum:` **各占一行**
- 值用**双引号**包裹
- **有缩进**（脚本的正则锚定行首空白，以避开注释）

改成多行拼接、换单引号、或顶格写都会导致替换失败。
脚本有 `grep` 复验，失败会中止而非发出坏包。

### 本仓库必须保持 public

SPM 的 `.binaryTarget(url:checksum:)` 下载 zip 时**不带任何鉴权头**。
设为 private 会导致下游拉取时 404。

若必须私有化，见 core 仓库《脚本发布教程》§2.4 的两条出路：

| 方案 | 做法 | 代价 |
|---|---|---|
| B | xcframework 提交进本仓库，改用 `.binaryTarget(path:)` | 仓库每版膨胀几十 MB，需配 Git LFS |
| C | 改用 CocoaPods + 私有 spec repo | 放弃 SPM |

### 🔴 仓库里不能有非 ASCII 文件名

git 对非 ASCII 文件名会做八进制转义并加引号：

```
100644 blob 82df2201...	"ios\345\246\202\344\275\225..."
```

**SPM 的 git tree 解析器处理不了，会让整个包无法被任何下游依赖**：

```
error: the package at '/' cannot be accessed
  malformedResponse("unexpected tree entry ...")
```

2026-09-14 实测踩到过一次（`ios如何调用这个库.md`），已改为 `iOS-Integration-Guide.md`。

**文件内容可以是任何语言，只有文件名必须 ASCII。**

排查：

```bash
git ls-tree -r HEAD | grep '"'    # 有输出就是有问题
```

core 仓库的 `verify-release.sh` 已加入真实 `swift package resolve` 检查，
能在发布验收阶段拦住此类问题。

### 不要手动打 tag

tag 由 `release.sh` 创建，且必须指向**包含已更新 `Package.swift`** 的那个 commit。

手动打 tag 容易造成「tag 指向旧 commit → 下游拉到旧 zip URL」。
`verify-release.sh` 会检查这一项。
