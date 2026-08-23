# 小特蓝牙钥匙 for iOS 17

[![Build iOS 17 IPA](https://github.com/zwthys-cyber/TeslaBLEKey/actions/workflows/build.yml/badge.svg)](https://github.com/zwthys-cyber/TeslaBLEKey/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/zwthys-cyber/TeslaBLEKey)](https://github.com/zwthys-cyber/TeslaBLEKey/releases/latest)

面向 TrollStore 与 iOS 17 的 Tesla 本地蓝牙钥匙客户端。车辆发现、配对、认证、状态读取和控制均不使用 Tesla 账号、OAuth、Fleet API 或开发者后端。

基础 Phone Key 配对与门锁控制不要求 VIN；需要 Infotainment 完整身份的高级功能会在首次使用时要求一次性补全 VIN，并仅保存在本机。音乐封面是独立的联网增强功能，详见[隐私说明](docs/PRIVACY.md)。

> [下载最新 TrollStore IPA](https://github.com/zwthys-cyber/TeslaBLEKey/releases/latest)

文档：[架构与协议](docs/ARCHITECTURE.md) · [构建与发布](docs/BUILD.md) · [隐私说明](docs/PRIVACY.md) · [版本记录](CHANGELOG.md)

## 当前功能

- 自动扫描附近 Tesla，并默认选择估算距离最近的一辆；多车场景仍可手动改选
- 支持多车辆钥匙管理、快速切换和每辆车独立的本机自定义名称
- 支持回家、上班、离车、冬季预热及自定义动作组合场景
- 支持车辆端预约充电/预热计划与附近超级充电站信息
- 支持低电量、门窗未关及充电异常的本地通知；只在取得真实车辆状态时判断
- Apple Watch 配套应用通过附近 iPhone 中继常用控制，手表不保存车辆私钥
- 候选车辆显示平滑 RSSI、dBm 和基于广播功率估算的距离；已识别车辆显示真实车型
- 前台扫描全部 BLE 广播后仅保留符合 Tesla 官方本地名称格式的车辆，避免服务 UUID 广播缺失造成漏检
- 在设备 Keychain 中生成并保存每辆车独立的 P-256 密钥
- 发送 Tesla VCSEC `addKey` 请求，通过已有 NFC 钥匙卡在车内授权
- 钥匙授权后直接建立本地 Phone Key/VCSEC 会话；无需账号、网络或用户输入 VIN
- Phone Key 认证后直接提供基础 VCSEC 控制；首次使用完整控制时补全 VIN 并升级 VCSEC/Infotainment 会话
- 读取车锁、尾门、充电口、座舱温度和空调状态，控制结果以车辆状态为准
- 充电控制中心支持开始/停止充电、充电上限、电流以及充电枪、功率和剩余时间
- 座舱控制中心支持最大除霜、方向盘加热、保持空调、爱犬/露营、生化防御和过热保护
- 哨兵模式按车辆真实能力开放；新增本机状态诊断、更新时间与最近 20 条脱敏操作记录
- 顶部显示真实 Tesla 车型或车机蓝牙标识，并用绿色状态点表示已连接
- 独立车辆详情页分组显示电量、续航、充电电流/枪锁、四门四窗、前后备箱、温度、胎压、休眠、挡位、里程、软件更新和媒体状态
- Tesla 风格主页媒体卡在播放或暂停时保留，支持上一首、播放/暂停和下一首；根据车机返回的歌名和歌手优先匹配网易云专辑封面，并以 Apple 公共目录作精确匹配回退
- App 在前台时每 2 秒轻量同步一次车机媒体状态；从中控屏切歌、暂停或继续播放后，主页曲目信息和封面会自动更新，进入后台即停止同步
- 主页与车辆详情均支持下拉刷新本地车机状态；只读状态请求不进入车辆命令的重试循环，车机未返回数据时本轮读取会正常结束
- App 从后台回到前台时自动刷新车辆状态；蓝牙会话已断开时自动重新连接
- 主页车辆状态卡直接显示电池电量百分比与预计续航
- 主页状态卡仅上半部车型与连接状态可进入车辆详情；电量和续航保持纯展示，其后提供紧凑锁形按钮，轻点直接发送锁车或解锁命令
- 主页采用固定原生导航头：车型、“蓝牙车钥匙”和菜单始终停留在顶部，车辆信息与控制内容仅从标题下方开始滚动
- 主页卡片可按车辆分别拖动排序、隐藏并一键恢复默认布局
- 被动钥匙默认开启，可在菜单关闭；通过 iOS CoreBluetooth 状态恢复保持 Phone Key 会话，拉门认证和离车上锁由车辆执行
- 车辆详情按状态类别分批读取，避免 BLE 单次响应超过 MTU；车辆未返回的字段不会显示为零
- 配对前检查本机公钥是否已在车机白名单，避免重复添加钥匙
- 上锁、解锁、驾驶授权、开启前备箱、开关电动后备箱、充电口、空调、温度、车窗通风、闪灯和鸣笛
- 前备箱和驾驶授权使用 Face ID、Touch ID 或设备密码二次确认
- Face ID 保护可按车辆设置为关闭、仅保护解锁/前备箱/驾驶授权，或保护全部控制
- 驾驶授权强制升级完整 VCSEC 会话并发送现代 `REMOTE_DRIVE` 指令，不使用无确认的旧协议路径
- 完整控制首次使用时一次性补全 VIN，并按 Tesla 官方 BLE 广播哈希校验当前车辆；VIN 仅保存在本机
- 提供锁车、解锁、空调、开始充电、闪灯和鸣笛的 Siri/快捷指令入口；仍只通过本地蓝牙执行
- 原创黑白 App 图标与紧凑车辆状态卡，不用大型模型遮挡首屏控制
- 单一门锁主操作、紧凑车辆控制带，以及控件内的执行进度和成功反馈
- 统一的无弹跳动效语言，并完整支持“减弱动态效果”
- GitHub Actions 编译无签名 IPA，供 TrollStore 安装

协议层使用固定到提交 `1cfc8ee366d59320ae813e6e1f9f4ddf7bf3ead1` 的
[`zwthys-cyber/TeslaBLEKeyKit`](https://github.com/zwthys-cyber/TeslaBLEKeyKit)。该分支基于上游 TeslaBLEKeyKit，增加 CoreBluetooth 状态恢复和被动钥匙连接处理；消息定义来源于 Tesla 官方
[`vehicle-command`](https://github.com/teslamotors/vehicle-command)。依赖固定提交是为了确保 App 构建与 CI 测试使用同一份已审查代码。

网易云封面搜索使用固定到提交 `8626b8fe628144e051dd9e07180850d253c808f2` 的原生 Swift
[`NeteaseCloudMusicAPI-Swift`](https://github.com/Lincb522/NeteaseCloudMusicApi-Swift)，仅调用匿名歌曲搜索并读取专辑封面，不使用登录、Cookie、播放或解灰接口。

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

1. 在 macOS 26/Xcode 26.2 上检出 App 实际固定的 TeslaBLEKeyKit 分支并运行密码学与协议测试；
2. 用 XcodeGen 生成工程；
3. 为真实 iPhone 编译 Release；
4. 编译并嵌入 watchOS 10 配套应用；
5. 生成 `TeslaBLEKey-unsigned.ipa` artifact。

工作流使用 Node 24 版本的 `actions/checkout@v6` 与 `actions/upload-artifact@v6`，避免 GitHub 托管 Runner 的 Node 20 弃用警告。

普通安装请直接从 [Releases](https://github.com/zwthys-cyber/TeslaBLEKey/releases/latest) 下载 IPA；Actions artifact 用于检查每次提交的开发构建。

## 本机编译

需要 Xcode 26.2、XcodeGen 和联网的 Swift Package Manager：

```bash
brew install xcodegen
xcodegen generate
open TeslaBLEKey.xcodeproj
```

默认 bundle identifier 是 `com.local.teslablekey`，可以在 `project.yml` 中修改。

完整的 CI、依赖固定策略、无签名 IPA 结构和发布检查见[构建与发布文档](docs/BUILD.md)。

## 重要限制

- 必须在真车上完成最终验证；模拟器无法模拟 Tesla BLE 外设或 NFC 钥匙卡授权。
- iOS 后台蓝牙受系统调度限制，本版本不承诺完全退出 App 后的无感靠近解锁。
- Apple Watch 控制依赖已配对 iPhone 可达并由手机执行 BLE 命令；Face ID 保护的操作必须回到 iPhone 完成。
- 本地车辆提醒只在 App 刷新或系统恢复蓝牙会话并取得真实状态时触发，不是 Tesla 云端推送。
- Tesla 本地蓝牙协议不提供车辆当前已安装的软件版本，因此详情页不显示占位行；车机返回更新信息时才显示待安装版本和更新状态。
- Tesla 本地蓝牙媒体协议不返回封面或循环模式，也不提供循环控制指令；封面通过免登录的网易云第三方接口精确匹配，失败时回退 Apple 公共目录或默认图标，单曲循环无法通过本地 BLE 控制。
- 2021 年以前的部分 Model S/X 不支持新的 Vehicle Command Protocol。
- 后备箱关闭仅适用于配备电动尾门且支持对应本地指令的车型；前备箱出于硬件安全设计只能远程打开。
- 这不是 Tesla 官方产品。首次测试时务必携带实体钥匙卡，不要把手机作为唯一钥匙。
- 开前备箱、后备箱和鸣笛等操作具有现实安全影响，确认车辆周围安全后再操作。

## 许可证

应用代码采用 MIT License。第三方依赖按其各自许可证分发。
