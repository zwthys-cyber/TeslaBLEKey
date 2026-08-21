# Tesla BLE Key for iOS 17

纯本地 Tesla 蓝牙钥匙实验性客户端。不使用 Tesla 账号、OAuth、Fleet API 或后端服务器。

## 当前功能

- 输入 VIN 并发现对应车辆 BLE 广播
- 自动扫描附近 Tesla，按信号强度排列并校验所选车辆与 VIN
- 在设备 Keychain 中生成并保存每辆车独立的 P-256 密钥
- 发送 Tesla VCSEC `addKey` 请求，通过已有 NFC 钥匙卡在车内授权
- 建立 Tesla Vehicle Command Protocol 加密会话
- 上锁、解锁、开启前后备箱、闪灯和鸣笛
- GitHub Actions 编译无签名 IPA，供 TrollStore 安装

协议层使用固定到提交 `a407b05bd93de70f91cd6318fb8a2320a063d101` 的
[`swift-tesla-ble`](https://github.com/shoujiaxin/swift-tesla-ble)，其消息定义来源于 Tesla 官方
[`vehicle-command`](https://github.com/teslamotors/vehicle-command)。依赖固定提交是为了避免构建时自动拉取未经审查的新代码。

## 配对

1. 在 TrollStore 中安装 Actions 生成的 IPA。
2. 打开蓝牙并允许 App 使用蓝牙。
3. 坐进车辆，携带一张已经授权的 Tesla NFC 钥匙卡。
4. 从自动扫描列表选择附近车辆，首次输入 17 位 VIN；App 会验证 VIN 哈希与所选车辆一致。
5. App 提示后，把钥匙卡放到中控台读卡区域，并在车机屏幕确认。
6. 车机显示成功后，点“车机已确认，验证连接”。

密钥使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，不会同步或迁移。卸载 App、清理
Keychain 或换机后必须重新配对。忘记车辆时，还应在车机“控制 > 锁”中删除旧钥匙记录。

## GitHub 编译

将此目录作为仓库推送到 GitHub。Actions 中的 **Build iOS 17 IPA** 会：

1. 在 macOS/Xcode 26 上运行协议库的密码学与协议测试；
2. 用 XcodeGen 生成工程；
3. 为真实 iPhone 编译 Release；
4. 生成 `TeslaBLEKey-unsigned.ipa` artifact。

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
