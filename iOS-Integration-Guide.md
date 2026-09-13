# iOS 集成指南

> 面向：不使用 gem 官方 iOS 代码，从空工程接入 `gemstone-swift` 的 iOS 开发者
> 目标：跑通「创建以太坊钱包 → 查余额 → 发交易」
> 延伸阅读（在 **core 仓库**，不在本仓库）：
> `gem私钥管理.md` · `rust回调原生端写好的接口(功能).md` · `安卓如何使用gem从0开发钱包.md`

---

## ⚠️ 先读这一段

本文 Swift 代码里的符号名，**大部分已从 gem 官方 iOS 代码实测核对**（见文末验证说明），少部分按 UniFFI 命名规则推导。

落地前以你实际拉到的 `Gemstone.swift` 为准——在 Xcode 里对 `import Gemstone` 按住 ⌘ 点进去就能看到全部接口。

---

## 目录

1. [先搞清楚三者关系与许可证边界](#1-先搞清楚三者关系与许可证边界)
2. [向 core 团队要什么](#2-向-core-团队要什么)
3. [一个必须先做对的决定](#3-一个必须先做对的决定)
4. [工程搭建](#4-工程搭建)
5. [四个核心文件](#5-四个核心文件)
6. [完整调用流程](#6-完整调用流程)
7. [API 参考](#7-api-参考)
8. [七个注意点](#8-七个注意点)
9. [已知缺口](#9-已知缺口)
10. [落地检查清单](#10-落地检查清单)

---

## 1. 先搞清楚三者关系与许可证边界

这是第一次接触最容易犯迷糊的地方，**而且搞错有法律后果**。

### 三个名字

```
gem 仓库（GPL-3.0）
├── core/              ← MIT 许可证 ⭐ 你能用的
│   └── gemstone/      ← Rust crate「引擎」
├── ios/               ← GPL-3.0，官方 App
└── android/           ← GPL-3.0，官方 App

              │ 编译 + UniFFI 生成绑定
              ▼
      gemstone-swift   ← 你依赖的东西
```

| 名字 | 是什么 |
|---|---|
| **gem** | 整个 monorepo（Rust core + 官方双端 App） |
| **core/gemstone** | Rust crate，真正的引擎源码 |
| **gemstone-swift** | `core/gemstone` 编译成 `.a` + Swift 绑定后的**分发包** |

> ⭐ **`gemstone-swift` 不是「另一个库」，它就是 gem 的 core 的分发形态。**
> 「调用 gemstone-swift」= 「调用 gem 的 core」，不是绕过 gem。

### 🔴 许可证：不是可选项

实测确认：

```
gem 仓库根 LICENSE  →  GNU GPL-3.0
core/LICENSE        →  MIT
ios/ android/       →  无独立 LICENSE，随根 = GPL-3.0
```

| 你怎么用 | 后果 |
|---|---|
| 依赖 `gemstone-swift`（= `core/`，MIT） | ✅ **可商用，无传染** |
| fork 或复制 `ios/` 下的代码 | 🔴 **GPL-3.0 传染，你整个 App 都得开源** |

> ⚠️ gem 仓库里有一整套现成的 iOS 代码（2000+ 文件），**看着很好用，但一行都不能抄。**
> 可以**读它学设计**，不能复制粘贴。本文里出现的 gem 官方代码片段均为「说明其做法」，不是让你照搬。

### 你本机不需要 gem 仓库

| 角色 | 要 clone gem 吗 |
|---|---|
| core 团队（发包的人） | ✅ 要 —— 编译 Rust、跑发布脚本 |
| **你（iOS 开发）** | ❌ **不要** —— 只加一行 SPM 依赖 |

**不需要装 Rust、不需要 core 源码、不需要任何额外工具链。**

---

## 2. 向 core 团队要什么

| # | 要什么 | 说明 |
|:---:|---|---|
| 1 | **`gemstone-swift` 仓库地址 + 版本号** | 例如 `https://github.com/your-org/gemstone-swift`，`from: "2.114.10"` |
| 2 | 🔴 **确认仓库是 public** | SPM 的 `binaryTarget` 下载 zip **不带鉴权头**，private 会 404 |
| 3 | **`Chain` 字符串取值表** | `Chain` 在 FFI 层是 String 不是枚举，以太坊是 `"ethereum"`（小写无下划线）。运行时查不到全量列表，必须要文档 |
| 4 | **Gem 后端 API 地址**（可选） | `GemGateway` 构造要传 `apiUrl`，但只被 `getTransactionScan()` 用。不调就传占位符 |
| 5 | **CHANGELOG** | `#[uniffi::export]` 签名变更会让你直接编译不过 |

---

## 3. 一个必须先做对的决定

`GemImportType` 有三个 case。做单链钱包看起来 `.singlePhrase` 更「对」，**但别用**。

| 选择 | 产生的 walletId | 以后想加链 |
|---|---|---|
| `.singlePhrase(words:chain:)` | `single_ethereum_0x9858...` | 🔴 **walletId 会变** → keystoreId 变 → 密钥文件找不到 → **用户钱包「消失」** |
| `.multicoinPhrase(words:chains:)` | `multicoin_0x9858...` | ✅ 不变，调 `addAccounts` 加链即可 |

原因在 Rust 侧：`multicoin` 的 walletId **永远由以太坊地址派生**，与启用了几条链无关。内部还会强制补上 Ethereum 来算 id，算完再从返回的 accounts 里过滤掉。

> ⭐ 今天传 `chains: ["ethereum"]`，明天传 `["ethereum", "polygon"]`，**walletId 完全一样**。
>
> **只做以太坊也用 `.multicoinPhrase`。** 选错了未来扩链要做一次痛苦的存量迁移。

---

## 4. 工程搭建

### 加依赖

**Xcode 图形界面**

```
File → Add Package Dependencies…
  https://github.com/your-org/gemstone-swift
  Dependency Rule：Up to Next Major Version → 2.114.10
```

**或 `Package.swift`**

```swift
dependencies: [
    .package(url: "https://github.com/your-org/gemstone-swift", from: "2.114.10")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "Gemstone", package: "gemstone-swift")
    ])
]
```

### 平台要求

| 项 | 要求 |
|---|---|
| iOS | 17.0+ |
| macOS | 15.0+ |
| 架构 | arm64（真机 + 模拟器） |
| Intel Mac | ❌ 不支持 |

### 第一个验证

```swift
import Gemstone

print(libVersion())      // 能打印出版本号 = XCFramework 加载成功
```

**这一行跑通再往下写。** 跑不通说明依赖没解析好，先解决那个。

---

## 5. 四个核心文件

### 5.1 `EthProvider.swift` —— 实现 Rust 要的网络接口

**这是必须实现的第一个东西。** Rust 不发 HTTP，它回调你。

```swift
import Foundation
import Gemstone

private let cacheTTLHeader = "x-gem-cache-ttl"

public actor EthProvider {                       // actor：天然线程安全
    private let session: URLSession
    private let rpcURL: URL

    public init(rpcURL: URL = URL(string: "https://ethereum.publicnode.com")!,
                session: URLSession = .shared) {
        self.rpcURL = rpcURL
        self.session = session
    }
}

extension EthProvider: AlienProvider {
    // Chain 在 FFI 层就是 String
    public nonisolated func getEndpoint(chain: Chain) throws -> String {
        guard chain == "ethereum" else {
            throw AlienError.RequestError(msg: "unsupported chain: \(chain)")
        }
        return rpcURL.absoluteString
    }

    public func request(target: AlienTarget) async throws -> AlienResponse {
        guard let url = URL(string: target.url) else {
            throw AlienError.RequestError(msg: "invalid url: \(target.url)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = alienMethodToString(method: target.method)
        // 🔴 私有 header 不能发给服务端
        request.allHTTPHeaderFields = target.headers?.filter { $0.key != cacheTTLHeader }
        request.httpBody = target.body

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            return AlienResponse(status: status.map(UInt16.init), data: data)
        } catch {
            if (error as NSError).domain == NSURLErrorDomain {
                throw AlienError.ResponseError(msg: error.localizedDescription)
            }
            throw error
        }
    }
}
```

> **关于 `x-gem-cache-ttl`**：Rust 用这个 header 告诉你「该请求可缓存」。它是**跨 FFI 的控制通道，不是给服务端看的**，发包前必须摘掉。要做缓存的话，用 `(method, url, body)` 的 SHA256 当 key。

### 5.2 `SimplePreferences.swift` —— 实现 Rust 要的存储接口

```swift
import Foundation
import Gemstone

public final class SimplePreferences: GemPreferences, @unchecked Sendable {
    private let defaults: UserDefaults
    private let namespace: String

    public init(namespace: String, defaults: UserDefaults = .standard) {
        self.namespace = namespace
        self.defaults = defaults
    }

    public func get(key: String) throws -> String? {
        defaults.string(forKey: namespace + key)
    }

    public func set(key: String, value: String) throws {
        defaults.set(value, forKey: namespace + key)
    }

    public func remove(key: String) throws {
        defaults.removeObject(forKey: namespace + key)
    }
}
```

Rust 用它存自己的一点内部状态（节点配置、鉴权 token 等），数据量很小。

> `@unchecked Sendable` 是因为 Rust 侧的 bound 是 `Send + Sync`。要么像这样自己保证线程安全，要么用 `actor`。

### 5.3 `WalletManager.swift` —— 创建钱包

```swift
import Foundation
import Gemstone

public let chainETH = "ethereum"

public struct WalletInfo: Sendable {
    public let walletId: String      // "multicoin_0x9858Ef..."
    public let keystoreId: String    // "f32a9e95-4904-533b-..."
    public let address: String
}

public final class WalletManager: @unchecked Sendable {

    private let keystoreURL: URL
    private let keystore: GemKeystore
    private let password: KeystorePassword

    public init(password: KeystorePassword = KeychainPassword()) throws {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("keystore", isDirectory: true)

        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.keystoreURL = base
        self.keystore = try GemKeystore(baseDir: base.path)
        self.password = password
    }

    // ── 助记词 ──
    private let mnemonic = GemMnemonic()

    public func generateMnemonic(wordCount: UInt8 = 12) throws -> [String] {
        try mnemonic.generate(wordCount: wordCount)
    }
    public func isValid(words: [String]) -> Bool { mnemonic.isValid(words: words) }
    public func isValidWord(_ word: String) -> Bool { mnemonic.isValidWord(word: word) }
    public func suggestWords(prefix: String, limit: UInt32? = 5) -> [String] {
        mnemonic.suggestWords(prefix: prefix, limit: limit)
    }
    public func findInvalidWords(_ words: [String]) -> [String] {
        mnemonic.findInvalidWords(words: words)
    }

    // ── 导入预览：不落盘、不需要密码 ──
    public func preview(words: [String]) throws -> [String] {
        try keystore.previewImport(
            import: .multicoinPhrase(words: words, chains: [chainETH])
        ).accounts.map(\.address)
    }

    // ── 创建 / 导入 ──
    public func createWallet(words: [String]) throws -> WalletInfo {
        try withPassword { pwd in
            let stored = try keystore.createStore(
                // 🔴 用 multicoinPhrase 而非 singlePhrase —— 见 §3
                import: .multicoinPhrase(words: words, chains: [chainETH]),
                password: pwd
            )
            guard let account = stored.accounts.first(where: { $0.chain == chainETH }) else {
                throw WalletError.accountNotFound
            }
            return WalletInfo(walletId: stored.walletId,
                              keystoreId: stored.keystoreId,
                              address: account.address)
        }
    }

    public func importPrivateKey(_ hex: String) throws -> WalletInfo {
        try withPassword { pwd in
            let stored = try keystore.createStore(
                import: .privateKey(value: hex, chain: chainETH),
                password: pwd
            )
            return WalletInfo(walletId: stored.walletId,
                              keystoreId: stored.keystoreId,
                              address: stored.accounts[0].address)
        }
    }

    public func deleteWallet(keystoreId: String) throws -> Bool {
        try keystore.delete(keystoreId: keystoreId)
    }

    // ── 签名（私钥不出 Rust）──
    public func sign(wallet: WalletInfo, input: GemSignerInput) throws -> [GemSignedTransaction] {
        try withPassword { pwd in
            try keystore.sign(keystoreId: wallet.keystoreId,
                              chain: chainETH, input: input, password: pwd)
        }
    }

    // 🔴 统一的密码取用 + 擦除包装，别让裸密码散落在业务代码里
    public func withPassword<R>(_ body: ([UInt8]) throws -> R) throws -> R {
        var bytes = try password.getOrCreate()
        defer { for i in bytes.indices { bytes[i] = 0 } }
        return try body(bytes)
    }
}

public enum WalletError: Error { case accountNotFound }
```

### 5.4 `KeychainPassword.swift` —— 密码管理

keystore 的密码是一个 **256-bit 随机设备密钥**，不是用户输入的口令。

```swift
import Foundation
import Security

public protocol KeystorePassword: Sendable {
    func getOrCreate() throws -> [UInt8]
}

public struct KeychainPassword: KeystorePassword {
    private let account = "gemstone.keystore.password"
    private let service = "com.yourorg.wallet"

    public init() {}

    public func getOrCreate() throws -> [UInt8] {
        if let existing = try read() { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &bytes) == errSecSuccess else {
            throw KeychainError.randomFailed
        }
        try write(bytes)
        return bytes
    }

    private func read() throws -> [UInt8]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.readFailed(status)
        }
        return [UInt8](data)
    }

    private func write(_ bytes: [UInt8]) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(bytes),
            // 🔴 ThisDeviceOnly：不进 iCloud Keychain，不随备份迁移到新设备
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.writeFailed(status) }
    }
}

public enum KeychainError: Error {
    case randomFailed
    case readFailed(OSStatus)
    case writeFailed(OSStatus)
}
```

> ⚠️ **生物识别不是默认绑定的。** `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` 只保证「设备解锁时可读」。要强制生物识别，需要用 `SecAccessControlCreateWithFlags` 加 `.biometryCurrentSet`。gem 官方也是把它做成可选 policy，默认不绑。

### 5.5 `EthService.swift` —— 查余额 / 发交易

```swift
import Foundation
import Gemstone

public final class EthService: @unchecked Sendable {
    private let gateway: GemGateway
    private let walletManager: WalletManager

    public init(provider: AlienProvider,
                preferences: GemPreferences,
                securePreferences: GemPreferences,
                walletManager: WalletManager) {
        self.gateway = GemGateway(
            provider: provider,
            preferences: preferences,
            securePreferences: securePreferences,
            apiUrl: "https://api.gemwallet.com"   // 不调 getTransactionScan 的话占位符即可
        )
        self.walletManager = walletManager
    }

    private let ethAsset = GemAsset(
        id: chainETH, chain: chainETH, tokenId: nil,
        name: "Ethereum", symbol: "ETH", decimals: 18,
        assetType: .native
    )

    /// 查 ETH 余额（返回 wei 字符串）
    public func balance(address: String) async throws -> String {
        try await gateway.getBalanceCoin(chain: chainETH, address: address).balance.available
    }

    /// 查 ERC-20 余额
    public func tokenBalances(address: String, tokenIds: [String]) async throws -> [GemAssetBalance] {
        try await gateway.getBalanceTokens(chain: chainETH, address: address, tokenIds: tokenIds)
    }

    /// 查代币元数据
    public func tokenData(contract: String) async throws -> GemAsset {
        try await gateway.getTokenData(chain: chainETH, tokenId: contract)
    }

    /// 费率档位，给用户选（慢 / 普通 / 快）
    public func feeRates() async throws -> [GemFeeRate] {
        try await gateway.getFeeRates(chain: chainETH, input: .transfer(asset: ethAsset))
    }

    /// 发一笔 ETH 转账，返回交易 hash
    public func sendETH(wallet: WalletInfo,
                        to: String,
                        amountWei: String,
                        feeRate: GemFeeRate) async throws -> String {
        let inputType = GemTransactionInputType.transfer(asset: ethAsset)

        // ① preload —— 从链上取 nonce + chainId
        let metadata = try await gateway.getTransactionPreload(
            chain: chainETH,
            input: GemTransactionPreloadInput(
                inputType: inputType,
                senderAddress: wallet.address,
                destinationAddress: to
            )
        )

        // ② load —— 估 gasLimit、算总费用
        let loadInput = GemTransactionLoadInput(
            inputType: inputType,
            senderAddress: wallet.address,
            destinationAddress: to,
            value: amountWei,
            gasPrice: feeRate.gasPriceType,
            memo: nil,
            isMaxValue: false,
            metadata: metadata            // ← nonce 在这里，原样透传给签名
        )
        let loadData = try await gateway.getTransactionLoad(chain: chainETH, input: loadInput)

        // ③ 签名 —— 私钥不出 Rust
        let signed = try walletManager.sign(
            wallet: wallet,
            input: GemSignerInput(input: loadInput, fee: loadData.fee)
        )

        // ④ 广播
        return try await gateway.transactionBroadcast(
            chain: chainETH,
            data: signed[0].data,
            options: GemBroadcastOptions(skipPreflight: false)
        )
    }
}
```

### 装配

```swift
let walletManager = try WalletManager()
let provider = EthProvider()
let prefs = SimplePreferences(namespace: "gateway.")
let securePrefs = SimplePreferences(namespace: "gateway.secure.")

let ethService = EthService(
    provider: provider,
    preferences: prefs,
    securePreferences: securePrefs,
    walletManager: walletManager
)
```

---

## 6. 完整调用流程

```
你写的两个实现 ──注入──┐
  EthProvider          │
  SimplePreferences    ▼
              ┌──────────────────────────────┐
              │  GemGateway / GemKeystore    │  ← Rust（XCFramework）
              └──────────────────────────────┘
                       │
  ┌────────────────────┼────────────────────┐
  ▼                    ▼                    ▼
创建钱包              查余额                发交易
  │                    │                    │
GemMnemonic()        getBalanceCoin      getTransactionPreload  ← nonce/chainId
 .generate(12)         ↓                    ↓
  ↓                  balance.available    getFeeRates            ← 费率档位
createStore(                                ↓
 .multicoinPhrase)                        getTransactionLoad     ← 估 gas
  ↓                                         ↓
{ walletId,                               keystore.sign          ← 🔴 私钥不出 Rust
  keystoreId,                               ↓
  accounts[0].address }                   transactionBroadcast   ← 返回 hash

               Rust 需要发 HTTP 时 ──回调──► 你的 EthProvider
```

**你的代码只接触 `keystoreId`（一个 UUID 字符串）和 `password`（字节数组）。**

---

## 7. API 参考

### `GemKeystore`

```swift
GemKeystore(baseDir: String) throws

previewImport(import:) throws -> GemWalletImport            // 不落盘、不要密码
createStore(import:password:) throws -> GemStoredWallet
addAccounts(keystoreId:password:chains:) throws -> [GemKeystoreAccount]
exportRecoveryPhrase(keystoreId:password:) throws -> [String]    // 仅「查看助记词」
exportPrivateKey(keystoreId:chain:password:) throws -> String    // 仅「导出私钥」
delete(keystoreId:) throws -> Bool
sign(keystoreId:chain:input:password:) throws -> [GemSignedTransaction]
signAuth(keystoreId:chain:hash:password:) throws -> String

// 顶层函数
keystoreIdForWallet(walletId: String) -> String
libVersion() -> String
```

### `GemMnemonic`

```swift
GemMnemonic()
  .generate(wordCount: UInt8) throws -> [String]     // 12 / 15 / 18 / 21 / 24
  .isValid(words: [String]) -> Bool
  .isValidWord(word: String) -> Bool
  .suggestWords(prefix: String, limit: UInt32?) -> [String]
  .findInvalidWords(words: [String]) -> [String]
```

熵源是 OS CSPRNG（`getrandom`），非用户态 PRNG。

### `GemGateway`

```swift
GemGateway(provider:preferences:securePreferences:apiUrl:)

// 余额
getBalanceCoin(chain:address:) async throws -> GemAssetBalance
getBalanceTokens(chain:address:tokenIds:) async throws -> [GemAssetBalance]

// 代币
getTokenData(chain:tokenId:) async throws -> GemAsset
getIsTokenAddress(chain:tokenId:) async throws -> Bool

// 交易
getTransactionPreload(chain:input:) async throws -> GemTransactionLoadMetadata
getFeeRates(chain:input:) async throws -> [GemFeeRate]         // ⚠️ 不叫 getTransactionFeeRates
getTransactionLoad(chain:input:) async throws -> GemTransactionData
transactionBroadcast(chain:data:options:) async throws -> String
getTransactionStatus(chain:request:) async throws -> GemTransactionUpdate

// 链信息
getChainId(chain:) async throws -> String
getBlockNumber(chain:) async throws -> UInt64
```

### 你要实现的两个 protocol

```swift
public protocol AlienProvider {
    func getEndpoint(chain: Chain) throws -> String
    func request(target: AlienTarget) async throws -> AlienResponse
}

public protocol GemPreferences {
    func get(key: String) throws -> String?
    func set(key: String, value: String) throws
    func remove(key: String) throws
}

// 相关类型
AlienTarget(url: String, method: AlienHttpMethod,
            headers: [String: String]?, body: Data?)
AlienResponse(status: UInt16?, data: Data)
alienMethodToString(method: AlienHttpMethod) -> String
```

---

## 8. 七个注意点

| # | 点 | 说明 |
|:---:|---|---|
| **1** | 🔴 **用 `.multicoinPhrase` 不用 `.singlePhrase`** | 见 §3。选错未来扩链要做存量迁移 |
| **2** | 🔴 **password 用完立刻清零** | 用 `withPassword { }` 这类包装强制执行，别散落在业务代码里 |
| **3** | **`Chain` 是 String 不是枚举** | 传 `"ethereum"`（小写无下划线）。写错只有运行期报错 |
| **4** | **HTTP status 是 `UInt16?`** | `status.map(UInt16.init)`，因为 Rust 侧是 `Option<u16>` |
| **5** | **错误类型是 `AlienError`** | Swift 是 `Error` 后缀，**Kotlin 才是 `AlienException`**。只能抛 protocol 声明的类型 |
| **6** | **线程安全是硬要求** | Rust bound 是 `Send + Sync`。用 `actor`（推荐）或 `@unchecked Sendable` 自己保证 |
| **7** | **助记词页面禁用截图** | `FLAG_SECURE` 的 iOS 等价物：监听 `UIScreen.capturedDidChangeNotification` + `isCaptured` |

### 关于第 5 点：只能抛声明的错误

```swift
// ✅ 正确
throw AlienError.RequestError(msg: "invalid url")

// ❌ 危险：抛未声明的类型可能导致未定义行为或 panic 穿 FFI 边界
throw MyCustomError.somethingWrong
```

在 `request` 里 catch 掉所有自定义错误，映射成 `AlienError` 再抛。

### 建议：自己包一层门面

gem 官方的做法（gem 仓库 `ios/Packages/Keystore/Sources/Types/Mnemonic.swift`）值得学：

```swift
internal import Gemstone        // Swift 6 的访问级别 import

public enum Mnemonic {
    private static let gemMnemonic = GemMnemonic()

    public static func generateWords(wordCount: UInt8 = 12) throws -> [String] {
        try gemMnemonic.generate(wordCount: wordCount)
    }
    // ...
}
```

好处：

- `internal import` 让 `Gemstone` 不外泄到你的 public API，上游改名不会波及整个 App
- 可以加默认值（`wordCount: UInt8 = 12`）、改成更 Swift 的命名
- 换引擎或 mock 测试时只改这一层

---

## 9. 已知缺口

### 没有 `verify` 接口

Rust 的 `FileKeystore` 有 `verify` / `get_meta` / `list` / `change_password`，但**都没导出到 UniFFI**。所以你没法直接问「这个 keystore 文件能用当前密码解开吗」。

变通办法：

```swift
// 助记词钱包：addAccounts 内部会真解密，还顺带返回地址供核对
_ = try keystore.addAccounts(keystoreId: id, password: pwd, chains: [chainETH])

// 私钥钱包：addAccounts 会显式报错，改用 signAuth 签一个 dummy hash
_ = try keystore.signAuth(keystoreId: id, chain: chainETH,
                          hash: Data(repeating: 0, count: 32), password: pwd)
```

> ⚠️ **不要用 `exportRecoveryPhrase` 做验证** —— 它会把助记词明文拉回 App 内存，为一次校验付这个代价不值。

需要这个功能的话，让 core 团队导出 `verify`，几行代码的事。

### nonce 是无状态的

gem 每次发交易都现查 `eth_getTransactionCount(addr, **latest**)`，**本地不存 nonce**。

- 好处：换设备、重装、多端同助记词都不会出问题
- 代价：**连续快速发两笔独立交易会撞 nonce**

如果产品允许连发，需要你在 UI 层加守卫（有 pending 交易时禁用发送按钮）。

### 交易加速 / 取消没有

gem 目前不支持。但 Rust 管线已经支持——`GemTransactionLoadInput.metadata` 里的 nonce 是**调用方传入并原样透传**到签名的，所以你把旧 nonce 填回去就能重发。

---

## 10. 落地检查清单

### 接入前

- [ ] 拿到 `gemstone-swift` 仓库地址与版本号
- [ ] 确认仓库是 **public**（否则 SPM 会 404）
- [ ] 书面确认 `Chain` 的以太坊取值
- [ ] 确认自己**没有**复制 gem 仓库 `ios/` 下的任何代码（GPL-3.0）

### 第一个里程碑（半天）

- [ ] `import Gemstone; print(libVersion())` 能跑 —— 证明 XCFramework 加载成功
- [ ] `GemMnemonic().generate(wordCount: 12)` 能出 12 个词
- [ ] `previewImport` 能派生出地址 —— 证明 keystore 派生链路通
- [ ] 实现 `AlienProvider` 后 `getBalanceCoin` 能查到真实余额 —— 证明反向回调通

> ⭐ **前四项跑通，剩下的就是体力活。** 建议先做一个只有几个按钮的调试页面验证这四步，再开始搭正式 UI。

### 上线前

- [ ] 所有 password 路径都有清零
- [ ] 密钥相关代码路径没有任何 log / 崩溃上报快照
- [ ] 助记词页面禁用截图与录屏
- [ ] Keychain 用了 `ThisDeviceOnly`，不进 iCloud 备份
- [ ] 真机 + 模拟器都验证过
- [ ] 签名 / 交易构造路径经过人工 Review

---

## 附：验证说明

本文档的 Swift API 命名分两类：

**已从 gem 官方 iOS 代码实测核对**（下表路径均相对 **gem 仓库根目录**，不在本仓库）：

| 符号 | 来源 |
|---|---|
| `GemKeystore(baseDir:)` | `ios/Packages/Keystore/Sources/LocalKeystore.swift` |
| `keystore.sign(keystoreId:chain:input:password:)` | 同上 |
| `GemGateway(provider:preferences:securePreferences:apiUrl:)` | `ios/Packages/Blockchain/Sources/Gateway/GatewayService.swift` |
| `gateway.getBalanceCoin(chain:address:)` | 同上 |
| `keystoreIdForWallet(walletId:)` | `ios/Packages/GemstonePrimitives/.../Wallet+GemstonePrimitives.swift` |
| `GemMnemonic()` 及其 5 个方法 | `ios/Packages/Keystore/Sources/Types/Mnemonic.swift` |
| `AlienProvider` 的两个方法签名 | `core/gemstone/tests/ios/GemTest/GemTest/Networking/Provider.swift` |
| `AlienResponse(status:data:)` · `alienMethodToString(method:)` | 同上 |
| `AlienError.RequestError(msg:)` | 同上 |
| `GemPreferences` 三个方法 | `ios/Packages/Blockchain/Sources/Gateway/GemstonePreferences.swift` |

**按 UniFFI 规则从 Rust 源码推导**（Rust 侧签名已核实，Swift 侧命名未见实物）：
`GemTransactionPreloadInput` / `GemTransactionLoadInput` / `GemSignerInput` / `GemAsset` / `GemFeeRate` / `GemBroadcastOptions` 等 Record 类型的字段名与构造形式。

落地时以你实际拉到的 `Gemstone.swift` 为准——Xcode 里 ⌘ 点 `import Gemstone` 即可查看。

---

*本文档由 AI 辅助整理，基于 gem 仓库 commit `820c415579`。*
