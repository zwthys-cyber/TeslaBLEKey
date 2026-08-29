# Tesla BLE 后台无感开锁与离车锁车技术说明

> 项目：小特蓝牙钥匙
> 当前版本：v2.3.2（Build 232）
> 平台：iOS 17 / SwiftUI / CoreBluetooth / Tesla VCSEC
> 文档用途：供 iOS、CoreBluetooth、Tesla Phone Key 协议专家及 Google Gemini 严格评审

## 1. 评审目标

本文说明当前 App 在以下场景中的真实实现：

- App 前台运行时拉动车门把手无感解锁。
- App 正常进入后台后，车辆重新靠近时恢复 Phone Key。
- iOS 因 BLE 事件恢复或重新启动 App 进程。
- 用户离开车辆后的自动锁车。
- 普通车辆控制连接与被动钥匙连接的隔离。
- 多车辆、强制退出、系统挂起和蓝牙中断的限制。

希望评审者重点寻找后台恢复、连接生命周期、认证挑战监听、状态竞争、重连策略以及离车锁车协议字段方面的真实缺陷。

## 2. 重要边界：RSSI 页面与 Phone Key 完全分离

“添加车辆”页面的 RSSI、估算距离和最近车辆排序只用于发现与选择车辆，不参与已经配对车辆的拉门认证或离车锁车判断。

```text
添加车辆 RSSI 链路：
BLE 广播 → RSSI 滤波 → 估算距离 → 候选车辆排序

Phone Key 链路：
已保存车辆身份 → 可恢复 BLE 连接 → VCSEC 会话
→ AuthenticationRequest → AES-GCM-TOKEN 响应
```

因此，页面显示“1 米内”或“约 5 米”不会直接决定车门是否解锁。

## 3. 系统能力声明

Info.plist 配置：

```yaml
UIBackgroundModes: [bluetooth-central]
```

用途：允许 App 在正常进入后台后继续处理 BLE Central 事件，并配合 CoreBluetooth State Preservation and Restoration 恢复连接、特征通知和待处理事件。

此能力不等于永久常驻。iOS 仍可以：

- 挂起 App 的普通代码执行。
- 合并或延迟 BLE 事件。
- 因内存、耗电、watchdog 或系统策略终止进程。
- 在用户从多任务界面强制划掉 App 后停止为其后台恢复。

因此 App 不能诚实承诺“任何系统状态下 100% 无感解锁”。实体钥匙卡必须作为安全后备。

## 4. 两条 BLE 连接的架构

当前架构刻意将主动命令与被动 Phone Key 分成两条连接。

### 4.1 普通命令连接

```swift
private var connection: BLEConnection?
private var tesla: TeslaVehicle?
private var legacyClient: LegacyVCSECClient?
```

职责：

- 锁车、解锁、后备箱、空调、充电和媒体等主动命令。
- 车辆状态读取。
- VIN-free Legacy VCSEC 或带 VIN 的现代会话。
- 主要在 App 前台使用。

### 4.2 独立被动钥匙连接

```swift
private var passiveConnection: BLEConnection?
private var passiveKeyClient: LegacyVCSECClient?
```

职责：

- 维持车辆原生 Phone Key 会话。
- 持续订阅车辆发来的认证请求。
- 在拉动车门把手时响应 `AuthenticationRequest`。
- 作为唯一需要尽量跨越后台状态的连接。

### 4.3 为什么不能共用连接

普通命令和被动挑战都会从 BLE 接收流读取消息。如果多个客户端共享同一 dispatcher/iterator，可能出现：

- 主动命令读取走门把手挑战。
- 被动监听器读取走命令响应。
- 命令超时，但消息实际被另一消费者消耗。
- 拉门挑战没有及时得到响应。

因此两条连接分别拥有独立的接收流，避免响应竞争。

## 5. 被动钥匙启动时机

被动钥匙默认开启：

```swift
passiveEntryEnabled =
    (defaults.object(forKey: AppStorageKeys.passiveEntryEnabled) as? Bool)
    ?? true
```

`VehicleController` 初始化时，如果车辆已经完成配对且被动钥匙开启，会立即创建可恢复的 Phone Key Central，而不是等待首页渲染完成：

```swift
if managesPassiveKey,
   isPaired,
   passiveEntryEnabled,
   !vehicleID.isEmpty {
    Task { [weak self] in
        await self?.bootstrapPassivePhoneKey()
    }
}
```

原因：iOS 可能只为了投递 CoreBluetooth 恢复事件而启动 App。如果等待 SwiftUI 页面任务，可能错过恢复窗口或延迟监听器建立。

## 6. CoreBluetooth 状态恢复标识

每辆当前车辆使用确定性的 restoration identifier：

```swift
let restorationID =
    "com.local.teslablekey.phonekey.\(vehicleID)"

let link = try BLEConnection(
    localName: vehicleID,
    restorationIdentifier: restorationID
)
```

设计目的：

- 同一车辆在进程恢复后得到同一条逻辑 Central。
- iOS 可以恢复已知外设连接和特征通知状态。
- 避免后台依赖按蓝牙名称重新扫描。
- 多车切换时每辆车的 restoration ID 不同。

TeslaBLEKeyKit 连接层还会保存首次识别到的 `CBPeripheral.identifier`。后续车辆重新进入范围时，优先对已知 Peripheral 提交系统托管的连接，而不是依赖后台扫描发现名称。

## 7. 建立专用 Phone Key 会话

核心流程：

```swift
private func startDedicatedPhoneKeyConnection(
    key: TeslaPrivateKey
) async throws {
    let restorationID =
        "com.local.teslablekey.phonekey.\(vehicleID)"
    let link = try BLEConnection(
        localName: vehicleID,
        restorationIdentifier: restorationID
    )
    passiveConnection = link

    try await link.connect(timeout: 30)

    let client = LegacyVCSECClient(
        connection: link,
        privateKey: key
    )
    try await client.startSession()
    client.startPassiveAuthenticationResponder()

    passiveKeyClient = client
    passiveKeyOnline = true
}
```

只有以下条件全部完成后，UI 才显示“钥匙在线”：

1. BLE 连接建立。
2. 本机私钥加载成功。
3. VCSEC 会话成功建立。
4. 被动认证响应循环已经启动。

仅仅 `CBPeripheral.state == connected` 不足以显示在线。

## 8. VIN-free VCSEC 会话

被动 Phone Key 使用已授权的本机 P-256 密钥，不要求 Tesla 账号、OAuth、Fleet API 或 VIN。

会话启动大致如下：

1. 使用本机公钥 SHA-1 前 4 字节形成 `keyID`。
2. 请求车辆临时 P-256 公钥。
3. 本机私钥与车辆临时公钥执行 ECDH。
4. 派生共享 AES 密钥。
5. 同步车辆计数器与本地计数器。
6. 发送签名的空认证响应，完成会话引导。

核心状态：

```swift
private let privateKey: TeslaPrivateKey
private let keyID: Data
private var sharedKey: Data?
private var counter: UInt32 = 0
```

## 9. 拉门无感解锁认证流程

保持 BLE 连接本身并不足以无感解锁。用户拉动车门把手时，车辆 VCSEC 会向已连接手机钥匙发送新的认证挑战。

### 9.1 连续监听

```swift
func startPassiveAuthenticationResponder() {
    guard passiveAuthenticationTask == nil else { return }

    passiveAuthenticationTask = Task { [weak self] in
        guard let self else { return }
        while !Task.isCancelled,
              let message = await self.iterator.next() {
            let response = Self.vcsecPayload(from: message)
            try await self.respondToAuthenticationRequest(
                in: response
            )
        }
    }
}
```

监听器没有周期性 60 秒超时，避免重建 iterator 时形成挑战丢失窗口。

### 9.2 挑战校验

当前代码校验：

- 消息包含 `FromVCSECMessage.authenticationRequest`。
- Session Token 长度必须为 20 字节。
- 请求的 Key ID 必须等于当前本机钥匙的 Key ID。
- 请求等级必须为 `UNLOCK` 或 `DRIVE` 对应的等级 1 或 2。
- 收到的车辆计数器会推动本地计数器向前。

```swift
guard let request = firstLengthDelimitedField(3, in: response),
      let session = firstLengthDelimitedField(2, in: request),
      let token = firstLengthDelimitedField(1, in: session),
      token.count == 20 else {
    return false
}
```

### 9.3 Token 绑定响应

App 使用 Session Token 作为 AES-GCM Additional Authenticated Data：

```swift
let authenticationResponse = enumField(
    1,
    requestedLevel
)
let unsigned = messageField(
    3,
    authenticationResponse
)

try await sendSigned(
    unsignedMessage: unsigned,
    authenticatedData: token,
    signatureType: 3 // AES_GCM_TOKEN
)
```

车辆验证响应后决定是否执行解锁或允许驾驶。

## 10. App 进入后台时的处理

App 根层监听 `scenePhase`：

```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .background {
        vehicle.noteAppMovedToBackground()
    }
}
```

进入后台时：

1. 标记 App 已进入后台。
2. 标记前台命令会话需要下次验证。
3. 停止后台周期性重试任务。
4. 释放普通命令客户端。
5. 保留独立的可恢复 Phone Key 连接。

```swift
func noteAppMovedToBackground() {
    appIsBackgrounded = true
    sessionNeedsForegroundValidation = true

    passiveReconnectTask?.cancel()
    passiveReconnectTask = nil

    commandConnectionPausedForBackground = true
    tesla?.disconnect()
    legacyClient?.close()
    tesla = nil
    legacyClient = nil
    phase = .idle
}
```

目的：Tesla 车辆和 iOS 的 BLE 资源有限。后台仅保留真正负责门把手挑战的连接，避免普通命令通道与 Phone Key 争抢连接槽位或接收流。

## 11. 后台断开与车辆重新靠近

控制器监听连接层通知：

- `BLEConnection.didDisconnectNotification`
- `BLEConnection.didBecomeReadyNotification`

当专用 Phone Key 连接断开：

```swift
passiveKeyOnline = false
await restoreDedicatedPhoneKeyConnection(on: disconnected)
```

当 iOS 托管的已知车辆连接重新变为 ready：

```swift
await restoreDedicatedPhoneKeyConnection(on: ready)
```

恢复时保留同一个 `BLEConnection`/`CBCentralManager` 对象：

```swift
try await link.connect(timeout: 45)
let key = try keyStore.load(for: vehicleID)
let client = LegacyVCSECClient(
    connection: link,
    privateKey: key
)
try await client.startSession()
client.startPassiveAuthenticationResponder()
```

如果恢复失败，不会立即销毁并用同一个 restoration ID 创建另一个 Central。这样做可能让 iOS 永久卡在 restoring 状态，直到 App 被终止。

## 12. 前台与后台重试策略

前台允许被动钥匙周期性恢复：

```text
首次延迟：5 秒
后续间隔：15 秒
```

进入后台后主动取消该循环。原因是普通 Swift 定时任务不会获得可靠后台执行时间，反复建立带超时的连接可能积累 continuation、耗电并增加 watchdog/jetsam 风险。

后台依赖的是 CoreBluetooth 托管连接和状态恢复事件，而不是 App 自己每 15 秒醒来扫描。

## 13. 回到前台后的恢复

回到前台时：

1. 标记 `appIsBackgrounded = false`。
2. 恢复或重建普通命令连接。
3. 检查专用 Phone Key 是否在线。
4. 现代会话发送副作用较小的车辆唤醒请求验证身份。
5. VIN-free 会话如果无法安全探活，则重建会话。
6. 重新读取车辆状态。

普通命令连接与被动连接仍保持分离。

## 14. 离车锁车的真实责任边界

当前 App 没有在“BLE 断开”事件中主动发送锁车命令。

```text
BLE 断开 ≠ App 自动调用 lock()
```

原因：

- 信号短暂中断可能来自人体遮挡、系统切换、车辆休眠或无线干扰。
- 在断开事件上直接锁车可能造成用户仍在车旁却被误锁。
- BLE 已断开时，App 通常也无法可靠发送锁车命令。
- Tesla 原生离车锁车应由车辆根据 Phone Key 存在性和车辆状态执行。

车辆端最终决定：

- 手机钥匙是否仍被认为在附近。
- 是否满足离车条件。
- 车门、座椅、挡位等状态是否允许落锁。
- 是否播放锁车提示音。

因此 App 能做的是保持正确的 Phone Key 会话与认证响应，不能完全替代车辆端的离车判断。

## 15. AuthenticationResponse 的 estimatedDistance 风险点

Tesla 旧 Phone Key 协议的 `AuthenticationResponse` 可能包含 `estimatedDistance` 字段。当前实现只编码：

```text
AuthenticationResponse.authenticationLevel
```

当前没有编码 `estimatedDistance`。Protobuf 未填写字段通常表现为默认值或字段缺失，具体车辆端语义需要结合准确 schema、Tesla 官方客户端实现和实车抓包确认。

这是本次希望外部评审重点核实的问题：

1. `estimatedDistance` 的字段号与数据类型是什么？
2. 单位是米、厘米、毫米、固定点数还是枚举？
3. 字段缺失与显式写入 0 的车辆端语义是否不同？
4. 车辆端是否使用该值参与离车落锁或仅用于诊断？
5. 官方手机钥匙如何计算该值？
6. 是否来自连接态 RSSI、扫描 RSSI、系统私有测距或多天线信息？
7. 在没有可靠测距来源时，填入估算值是否比保持字段缺失更危险？

不应将“添加车辆页面”的前台扫描距离直接塞入该字段，因为：

- 后台 Phone Key 通道不是同一条扫描链路。
- iOS 后台不保证持续获得扫描 RSSI。
- 页面 RSSI 可能来自不同 Peripheral 时刻和广播状态。
- 错误距离可能让车辆误判手机仍在旁边或已经离开。

## 16. 当前“钥匙在线”状态定义

UI 状态：

```text
被动钥匙关闭 → 灰色“钥匙关闭”
被动连接恢复中 → 橙色“钥匙恢复中”
会话和监听器就绪 → 绿色“钥匙在线”
```

`passiveKeyOnline` 只在以下步骤成功后设为 `true`：

- 专用 BLE 连接完成。
- VCSEC 会话成功。
- 被动认证 responder 启动。

但它仍然是 App 端状态，不代表车辆一定会在任何时刻接受认证。车辆端是否把钥匙显示为在线仍取决于车辆连接、休眠和安全状态。

## 17. 多车辆行为

当前只有一组：

```swift
passiveConnection
passiveKeyClient
```

因此后台 Phone Key 只跟随当前选中的车辆。切换车辆时：

1. 关闭上一辆车的普通连接和被动连接。
2. 加载新车辆独立的 Keychain 私钥和车辆资料。
3. 为新车辆创建新的 restoration identifier。
4. 建立新车辆的 Phone Key 会话。

App 不宣称多辆已添加车辆能够同时保持后台无感钥匙在线。并行维护多车可能争抢 iOS 与车辆 BLE 连接资源，还可能增加错误车辆响应风险。

## 18. 强制退出行为

正常返回桌面与从多任务界面向上强制划掉 App 是不同状态。

### 正常进入后台

CoreBluetooth 可以继续托管连接，并在特征事件或恢复事件到达时唤醒/恢复 App。

### 用户强制划掉 App

iOS 通常将其视为用户明确要求停止应用。系统不保证随后因为 BLE 事件重新启动它。因此：

- 不能保证强退后的无感解锁。
- App 无法可靠捕获“自己即将被用户强退”。
- 无法在强退后发送本地通知提醒用户。
- 车辆是否提示钥匙离线属于车辆端行为。

任何声称强退后仍 100% 后台常驻的普通 App，都需要非常谨慎验证其真实机制。

## 19. 当前诊断事件

App 记录脱敏时间线，包括：

```text
app.launch
app.scene.active
app.scene.background
ble.connect.begin
ble.connect.ready
ble.command.paused.background
ble.passive.bootstrap.ready
ble.passive.bootstrap.pending
ble.passive.disconnected
ble.passive.proximity.ready
ble.passive.restore.begin
ble.passive.restore.ready
ble.passive.restore.failed
ble.passive.challenge.received.level1
ble.passive.challenge.received.level2
ble.passive.challenge.responded.<毫秒>ms
ble.passive.challenge.failed
```

这些事件不记录 VIN、车辆位置、私钥、Token 或消息正文。

理想的实车问题时间线：

```text
app.scene.background
ble.command.paused.background
...
ble.passive.proximity.ready
ble.passive.restore.begin
ble.passive.restore.ready
ble.passive.challenge.received.level1
ble.passive.challenge.responded.XXms
```

如果拉门失败，可按缺失点区分：

- 没有 `proximity.ready`：CoreBluetooth/连接恢复问题。
- 有 `ready`、没有 `restore.ready`：VCSEC 会话恢复问题。
- 已 `restore.ready`、没有 `challenge.received`：车辆没有向此连接发挑战，或通知订阅异常。
- 收到 challenge、但 `challenge.failed`：Token、Key ID、计数器或加密响应问题。
- 已 responded 但车辆不解锁：车辆拒绝或距离/车辆状态判断问题。

## 20. 已知风险与待审查点

### 必须重点审查

1. `AuthenticationResponse.estimatedDistance` 缺失的真实车辆端影响。
2. 状态恢复时特征通知是否在会话重建前后被正确恢复。
3. `receiveMessages()` iterator 在连接恢复后是否可能持有旧 stream。
4. `startSession()` 与认证挑战同时到达时是否存在消息竞争。
5. 断开通知回调中立即等待 45 秒连接，是否可能阻塞后续恢复事件。
6. 后台恢复失败后只依靠系统 ready 事件，是否存在永远不再触发的边缘状态。
7. `counter` 使用车辆计数器和 Unix 时间最大值的兼容性。
8. 多次状态恢复是否会重复注册通知或留下旧 responder。

### 建议审查

1. 是否需要在诊断中记录连接状态机阶段和失败分类，但仍保持脱敏。
2. 是否应记录挑战从接收到发送完成的分段耗时。
3. 是否应为 Phone Key 添加无副作用的周期性健康状态，但不能依赖后台定时器。
4. 是否有必要为 Keychain 配置不同的可访问级别，以兼顾锁屏后台使用与安全性。
5. 是否需要检测系统低电量模式、蓝牙关闭和权限变化。

## 21. 请勿提出的伪解决方案

除非能提供可运行且符合 App Store 规则的证据，否则不应把以下方案作为主要答案：

- 无限后台定时器。
- 静默音频保活。
- 持续定位保活但 App 实际没有定位业务。
- 私有 API。
- 强退后自行重启 App。
- 用前台扫描 RSSI 直接替代 Tesla Phone Key 协议。
- BLE 一断开就盲目发送锁车命令。
- 声称可以绕过 iOS 调度实现 100% 常驻。

## 22. 建议 Gemini 的评审指令

请以资深 iOS CoreBluetooth、Apple 后台执行机制、BLE 安全协议和 Tesla Phone Key 逆向工程专家的角度严格评审，不要只总结本文。

请按以下格式回答：

1. 必须修改：会直接造成后台无感开锁或离车锁车失败的问题。
2. 建议优化：提高恢复速度、稳定性、诊断能力或功耗表现的问题。
3. 当前已经合理：无需为了复杂度而修改的设计。
4. 无法确认：需要官方 schema、实车抓包或设备日志才能判断的部分。

重点回答：

- 当前双连接设计是否正确。
- App 启动时立即创建可恢复 Central 是否合理。
- 后台释放命令连接、保留被动连接是否正确。
- CoreBluetooth restoration identifier 和已知 Peripheral 直连策略是否完整。
- responder 的 AsyncStream 生命周期是否存在丢消息或并发读取风险。
- `AuthenticationResponse.estimatedDistance` 是否必须填写，以及准确编码和来源。
- 离车锁车是否需要 App 额外动作，还是应完全由车辆端判断。
- 当前前后台重连策略是否会形成死循环、重复 Central 或 continuation 泄漏。
- 强退、系统终止、蓝牙关闭后，各自能达到什么可靠性边界。

如果建议修改，请给出：

- 明确的协议或 Apple 文档依据。
- 可以直接落地的 Swift 代码或状态机伪代码。
- 对功耗、延迟、App Store 合规性和错误锁车风险的影响。
- 不要把无法从公开 API 取得的数据假设为已经可用。

## 23. 一句话总结

当前 App 通过“前台命令连接 + 独立可恢复 Phone Key 连接”隔离主动控制与门把手挑战，后台只保留后者，并使用已授权本机密钥响应车辆的 Token 绑定认证请求；真正的解锁与离车落锁仍由车辆决定。当前最值得外部复核的协议点，是 `AuthenticationResponse.estimatedDistance` 缺失的语义以及 CoreBluetooth 恢复后接收流和通知订阅的完整性。
