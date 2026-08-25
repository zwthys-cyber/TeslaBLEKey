# 架构与协议

本文对应 App `2.3.1` 与 `main` 分支。小特蓝牙钥匙不通过 Tesla 账号或 Fleet API 控车，车辆链路如下：

1. `NearbyTeslaScanner` 使用 CoreBluetooth 扫描附近广播，并校验 Tesla 本地名称格式。
2. App 为每辆车在 Keychain 生成独立 P-256 私钥。
3. `LegacyVCSECClient` 建立无需 VIN 的 Phone Key 引导会话，并通过车内已有 NFC 钥匙卡授权公钥。
4. 基础 VCSEC 会话负责 Phone Key 认证、基础门锁/开闭件命令和 Vehicle Status 状态回读。
5. 需要 Infotainment 完整身份的功能使用本机保存的 VIN 建立现代会话；VIN 会与当前车辆 BLE 广播标识校验。
6. 充电、座舱与哨兵命令复用同一条串行化会话；能力与可调范围由车辆状态决定。
7. 诊断历史只在本机保留最近 20 条命令名称、时间与结果，不记录 VIN、位置或密钥。

## 主要模块

- `Bluetooth/NearbyTeslaScanner.swift`：扫描、RSSI 平滑、距离估算和候选车过滤。
- `Bluetooth/LegacyVCSECClient.swift`：VIN-free 配对及会话引导。
- `Model/VehicleController.swift`：连接生命周期、车辆状态、命令调度、媒体同步和错误呈现。
- 多车辆索引保存在本机偏好中，每辆车使用独立 Keychain 密钥、VIN、车型、自定义名称、安全设置、场景、主页布局和操作记录；旧版单车辆记录会自动迁移。添加失败或取消会原子回滚到原车辆，切换前会清空瞬时车辆快照。
- `Views/VehicleControlView.swift`：固定主页导航头、车辆卡、媒体卡和控制区。
- `Views/VehicleDetailView.swift`：按类别分批读取并展示车辆详情。
- `Model/MediaArtworkLookup.swift`：网易云封面精确匹配与 Apple 目录回退。
- `Views/AutomationScenesView.swift`：每辆车独立的预设/自定义场景与串行动作执行。
- `Views/ScheduleAndChargingSitesView.swift`：车辆端预约与附近超级充电站。
- `Model/VehicleAlertManager.swift`：基于刷新快照的本地通知与重复抑制。
- `App/WatchBridge.swift`：Apple Watch 与 iPhone 命令中继和状态快照。

## 后台与被动钥匙

多车模式下后台 Phone Key 只跟随当前选中的车辆，切换时关闭上一辆车的连接并为新车辆重建会话；应用不承诺多辆车同时在线。

被动钥匙默认开启。命令会话和原生 Phone Key 始终各自拥有 BLE 连接及接收流（包括 VIN-free 模式）：前者承载主动命令，后者使用无周期超时的连续事件流监听车辆在拉动门把手时发送的 `AuthenticationRequest`。监听器校验目标密钥、20 字节会话令牌及 UNLOCK/DRIVE 等级，再以令牌作为 AES-GCM 附加认证数据返回 `AES_GCM_TOKEN` 响应，并将不含车辆身份的响应耗时写入本地诊断。Phone Key 连接单独配置固定 CoreBluetooth restoration identifier，在 App 进程启动时立即创建；首次发现车辆后还会保存该车辆的 CoreBluetooth 外设 UUID，后续后台直接提交由系统托管的已知外设连接，避免依赖后台名称扫描。车辆回到范围并恢复特征通知后，连接层通知 App 自动重建 Phone Key 会话与挑战监听器。普通命令连接只在 scene phase 为 active 时建立，重复的前台恢复请求会被合并；系统因 BLE 事件在后台拉起 App 时不会误建控制通道。App 进入后台时释放普通命令连接，即使 Phone Key 尚处于恢复中也不与其争抢车辆 BLE 会话；Siri/快捷指令控制器明确禁止创建第二条 Phone Key 会话。最终的距离判定、解锁、离车上锁和钥匙丢失提示由车辆执行；iOS 仍可根据系统资源暂停或延迟后台 BLE 工作，因此实体钥匙卡始终是安全后备。

Apple Watch 不持有 P-256 车辆私钥。手表通过 WatchConnectivity 将命令交给附近 iPhone，再由手机现有认证 BLE 会话执行；手机不可达时不会排队执行车辆安全命令。

预约计划写入车辆而不是使用 App 本地定时器，并使用车辆返回的位置创建位置绑定计划。超级充电站同样来自车辆本地协议响应；查询会等待整车或媒体读取释放串行 BLE 槽位，保留最后一次有效列表，并展示车辆返回的空闲桩、总桩数、故障桩、功率、距离、续航范围标识和时间戳。

## 状态与媒体同步

整车状态在连接、手动下拉刷新和 App 回到前台时读取。为避免 BLE 单次响应超过 MTU，详情状态按 Charge、Climate、Closures、Tire、Drive、Software Update 和 Media 分批请求。只读 VehicleData 请求明确禁用车辆命令的可重试循环，因此车机未响应时请求会返回而不是无限重发。完整刷新期间媒体轮询会让路，并阻止第二个完整刷新进入，避免 BLE receiver 互相等待。

Tesla 不会把中控屏切歌主动推送给本 App。主页在前台连接期间每 2 秒只轮询 MediaState 与 MediaDetailState；进入后台立即停止，不重复读取电池或车门等整车数据。

控制命令只有收到协议成功结果才进入状态确认阶段。门锁和开闭件随后读取 VCSEC Vehicle Status；充电、座舱、车窗与哨兵分别只回读对应 CarServer 状态。后备箱会短时轮询打开、半开、移动、关闭或解锁失败状态；车辆未确认关闭时不会伪报成功。预约星期严格使用 Tesla 定义的 `SUN=1, MON=2, ... SAT=64` 位掩码。

## 固定依赖

- `zwthys-cyber/TeslaBLEKeyKit`：`d5da62c003ac6e2e0d8695f910957dd5708c82d7`
- `Lincb522/NeteaseCloudMusicApi-Swift`：`8626b8fe628144e051dd9e07180850d253c808f2`

具体固定值以仓库根目录的 `project.yml` 为唯一事实来源；CI 必须测试同一 TeslaBLEKeyKit 提交。
