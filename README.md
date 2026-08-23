# 小特蓝牙钥匙 for iOS 17

[![Build iOS 17 IPA](https://github.com/zwthys-cyber/TeslaBLEKey/actions/workflows/build.yml/badge.svg)](https://github.com/zwthys-cyber/TeslaBLEKey/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/zwthys-cyber/TeslaBLEKey)](https://github.com/zwthys-cyber/TeslaBLEKey/releases/latest)

纯本地 Tesla 蓝牙钥匙客户端。不使用 Tesla 账号、OAuth、Fleet API、VIN 输入或后端服务器。

> [下载最新 TrollStore IPA](https://github.com/zwthys-cyber/TeslaBLEKey/releases/latest)

## 当前功能

- 自动扫描附近 Tesla，并默认选择估算距离最近的一辆；多车场景仍可手动改选
- 候选车辆显示平滑 RSSI、dBm 和基于广播功率估算的距离；已识别车辆显示真实车型
- 前台扫描全部 BLE 广播后仅保留符合 Tesla 官方本地名称格式的车辆，避免服务 UUID 广播缺失造成漏检
- 在设备 Keychain 中生成并保存每辆车独立的 P-256 密钥
- 发送 Tesla VCSEC `addKey` 请求，通过已有 NFC 钥匙卡在车内授权
- 钥匙授权后直接建立本地 Phone Key/VCSEC 会话；无需账号、网络或用户输入 VIN
- Phone Key 认证后直接提供基础 VCSEC 控制；首次使用完整控制时补全 VIN 并升级 VCSEC/Infotainment 会话
- 读取车锁、尾门、充电口、座舱温度和空调状态，控制结果以车辆状态为准
- 顶部显示真实 Tesla 车型或车机蓝牙标识，并用绿色状态点表示已连接
- 独立车辆详情页分组显示电量、续航、充电电流/枪锁、四门四窗、前后备箱、温度、胎压、休眠、挡位、里程、软件和媒体状态
- 车辆详情按状态类别分批读取，避免 BLE 单次响应超过 MTU；车辆未返回的字段不会显示为零
- 配对前检查本机公钥是否已在车机白名单，避免重复添加钥匙
- 上锁、解锁、驾驶授权、开启前备箱、开关电动后备箱、充电口、空调、温度、车窗通风、闪灯和鸣笛
- 前备箱和驾驶授权使用 Face ID、Touch ID 或设备密码二次确认
- 驾驶授权强制升级完整 VCSEC 会话并发送现代 `REMOTE_DRIVE` 指令，不使用无确认的旧协议路径
- 完整控制首次使用时一次性补全 VIN，并按 Tesla 官方 BLE 广播哈希校验当前车辆；VIN 仅保存在本机
- 提供锁车、闪灯和鸣笛的 Siri/快捷指令入口；仍只通过本地蓝牙执行
- 原创黑白 App 图标与紧凑车辆状态卡，不用大型模型遮挡首屏控制
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
4. App 按估算距离实时排列车辆并默认选择最近的一辆；附近有多辆车时，可核对车型、设备标识、dBm 和距离后手动改选。
5. App 提示后，把钥匙卡放到中控台读卡区域并在车机确认；看到新钥匙后，回到 App 点“已在车机确认，继续”。

密钥使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，不会同步或迁移。清理 Keychain 或换机后需要重新配对；卸载 App 前应先在 App 内忘记车辆，并在车机“控制 > 锁”中删除旧钥匙记录。

距离是根据 BLE 广播功率与平滑后的 RSSI 估算，会受车身遮挡、手机朝向和现场干扰影响；默认选择仅用于减少操作，不代替用户核对车辆。

## GitHub 编译

将此目录作为仓库推送到 GitHub。Actions 中的 **Build iOS 17 IPA** 会：

1. 在 macOS/Xcode 26 上运行协议库的密码学与协议测试；
2. 用 XcodeGen 生成工程；
3. 为真实 iPhone 编译 Release；
4. 生成 `TeslaBLEKey-unsigned.ipa` artifact。

工作流使用 Node 24 版本的 `actions/checkout@v6` 与 `actions/upload-artifact@v6`，避免 GitHub 托管 Runner 的 Node 20 弃用警告。

普通安装请直接从 [Releases](https://github.com/zwthys-cyber/TeslaBLEKey/releases/latest) 下载 IPA；Actions artifact 用于检查每次提交的开发构建。

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
- 后备箱关闭仅适用于配备电动尾门且支持对应本地指令的车型；前备箱出于硬件安全设计只能远程打开。
- 这不是 Tesla 官方产品。首次测试时务必携带实体钥匙卡，不要把手机作为唯一钥匙。
- 开前备箱、后备箱和鸣笛等操作具有现实安全影响，确认车辆周围安全后再操作。

## 许可证

应用代码采用 MIT License。第三方依赖按其各自许可证分发。
