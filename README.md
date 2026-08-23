# 小特蓝牙钥匙 for iOS 17

[![Build iOS 17 IPA](https://github.com/ac54u-mobile/TeslaBLEKey/actions/workflows/build.yml/badge.svg)](https://github.com/ac54u-mobile/TeslaBLEKey/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/ac54u-mobile/TeslaBLEKey)](https://github.com/ac54u-mobile/TeslaBLEKey/releases/latest)

纯本地 Tesla 蓝牙钥匙客户端。不使用 Tesla 账号、OAuth、Fleet API、VIN 输入或后端服务器。当前版本：**1.4.1**。

> [下载最新 TrollStore IPA](https://github.com/ac54u-mobile/TeslaBLEKey/releases/latest)

## 当前功能

- 自动扫描附近 Tesla；单车自动选择，多车显示实时信号强度并由用户确认
- 候选车辆显示平滑 RSSI、dBm 和基于广播功率估算的距离；已识别车辆显示真实车型
- 前台扫描全部 BLE 广播后仅保留符合 Tesla 官方本地名称格式的车辆，避免服务 UUID 广播缺失造成漏检
- 在设备 Keychain 中生成并保存每辆车独立的 P-256 密钥
- 发送 Tesla VCSEC `addKey` 请求，通过已有 NFC 钥匙卡在车内授权
- 钥匙授权后通过 Universal Message 承载的本地 Phone Key/VCSEC 会话读取 VehicleInfo 并认证；无需用户输入 VIN
- 配对前检查本机公钥是否已在车机白名单，避免重复添加钥匙
- 上锁、解锁、驾驶授权、开启前后备箱、闪灯和鸣笛
- 原创黑白 App 图标与简洁车辆舞台：搜索、配对、连接和执行始终呈现为同一辆车
- 单一门锁主操作、紧凑车辆控制带，以及控件内的执行进度和成功反馈
- 统一的无弹跳动效语言，并完整支持“减弱动态效果”
- GitHub Actions 编译无签名 IPA，供 TrollStore 安装

协议层使用固定到提交 `e186c5a2ade352b719cb53b92599619f2556b841` 的
[`TeslaBLEKeyKit`](https://github.com/misakatao/TeslaBLEKeyKit)，其消息定义来源于 Tesla 官方
[`vehicle-command`](https://github.com/teslamotors/vehicle-command)。依赖固定提交是为了避免构建时自动拉取未经审查的新代码。

## 配对

1. 在 TrollStore 中安装 Actions 生成的 IPA。
2. 打开蓝牙并允许 App 使用蓝牙。
3. 坐进车辆，携带一张已经授权的 Tesla NFC 钥匙卡。
4. 仅发现一辆时 App 自动选择；发现多辆时按信号强度排列，确认离手机最近的车辆后点击“添加车钥匙”。
5. App 提示后，把钥匙卡放到中控台读卡区域并在车机确认；看到新钥匙后，回到 App 点“已在车机确认，继续”。

密钥使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，不会同步或迁移。卸载 App、清理
Keychain 或换机后必须重新配对。忘记车辆时，还应在车机“控制 > 锁”中删除旧钥匙记录。

## GitHub 编译

将此目录作为仓库推送到 GitHub。Actions 中的 **Build iOS 17 IPA** 会：

1. 在 macOS/Xcode 26 上运行协议库的密码学与协议测试；
2. 用 XcodeGen 生成工程；
3. 为真实 iPhone 编译 Release；
4. 生成 `TeslaBLEKey-unsigned.ipa` artifact。

工作流使用 Node 24 版本的 `actions/checkout@v6` 与 `actions/upload-artifact@v6`，避免 GitHub 托管 Runner 的 Node 20 弃用警告。

下载 artifact，解压后将 IPA 分享给 TrollStore 安装。

## 本机编译

需要 Xcode 26、XcodeGen 和联网的 Swift Package Manager：

```bash
brew install xcodegen
xcodegen generate
open TeslaBLEKey.xcodeproj
```

默认 bundle identifier 是 `com.local.teslablekey`，可以在 `project.yml` 中修改。

## 重要限制

- 必须在真车上完成最终验证；模拟器无法模拟 Tesla BLE 外设或 NFC 钥匙卡授权。
- iOS 后台蓝牙受系统调度限制，本版本不承诺完全退出 App 后的无感靠近解锁。
- 2021 年以前的部分 Model S/X 不支持新的 Vehicle Command Protocol。
- 这不是 Tesla 官方产品。首次测试时务必携带实体钥匙卡，不要把手机作为唯一钥匙。
- 开前备箱、后备箱和鸣笛等操作具有现实安全影响，确认车辆周围安全后再操作。

## 许可证

应用代码采用 MIT License。第三方依赖按其各自许可证分发。
