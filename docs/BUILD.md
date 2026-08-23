# 构建与发布

## 环境

- iOS deployment target：17.0
- GitHub Runner：`macos-26`
- Xcode：26.2
- Swift Package Manager：解析 `project.yml` 中固定 revision
- 工程生成器：XcodeGen

## 本机构建

```bash
brew install xcodegen
xcodegen generate
open TeslaBLEKey.xcodeproj
```

默认 Bundle ID 为 `com.local.teslablekey`。真车 BLE 与 NFC 钥匙卡授权无法在模拟器验证。

## GitHub Actions

`.github/workflows/build.yml` 在 `main` push、Pull Request 和手动触发时运行两个 Job：

1. `Tesla protocol tests` 检出 `zwthys-cyber/TeslaBLEKeyKit` 的固定提交并执行 `swift test`。
2. `Build unsigned TrollStore IPA` 生成 Xcode 工程、解析固定依赖、以禁用代码签名的 Release 配置编译真实 iPhone 目标，并打包 `Payload/TeslaBLEKey.app`。

Artifact 名称为 `TeslaBLEKey-iOS17-TrollStore`，文件名为 `TeslaBLEKey-unsigned.ipa`。工作流使用 `actions/checkout@v6` 和 `actions/upload-artifact@v6`，避免旧 Node 20 Action 运行时警告。

## 发布检查

- `project.yml` 的 `MARKETING_VERSION` 与 Release tag 一致。
- README、架构文档与依赖 revision 一致。
- 协议测试和无签名 iPhone Release 构建全部通过。
- 下载 Actions artifact 并记录 SHA-256。
- TrollStore 真机安装后验证配对、重连、门锁、媒体同步和后台恢复；CI 不能替代真车测试。
