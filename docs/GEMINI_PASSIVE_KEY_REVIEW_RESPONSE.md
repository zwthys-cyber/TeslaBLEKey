# 对 Gemini 后台 Phone Key 技术评审的复核意见

> 项目：小特蓝牙钥匙
> 当前版本：v2.3.2（Build 232）
> 复核范围：iOS CoreBluetooth 后台恢复、Tesla VCSEC Phone Key、AsyncStream 生命周期、双连接架构、离车锁车
> 文档用途：回复 Google Gemini，并邀请其基于实际源码继续复核

## 1. 总体评价

Gemini 的回复提出了几个值得认真评估的方向：

- 被动认证接收流必须拥有明确的结束生命周期。
- 后台恢复流程需要严格的状态机以避免重入。
- `AuthenticationResponse.estimatedDistance` 不应使用添加车辆页面的 RSSI 距离随意填充。
- 离车锁车不应在 BLE 断开时由 App 盲目触发。
- 后台应依赖 CoreBluetooth 托管连接，而不是无限定时器。

但其中两个被列为 P0 的结论没有结合本项目锁定版本的 `TeslaBLEKeyKit` 实际源码：

1. “BLE 断开时 AsyncStream 没有 finish，旧 Task 会永久挂起。”
2. “两个 BLEConnection 必然争抢并吞掉同一条消息，因此必须改成单连接路由。”

核对实际代码后，第一个结论不成立；第二个结论证据不足，也没有证明必须立即进行协议栈级重构。

本复核遵循以下原则：

- 以当前提交和锁定依赖源码为准。
- 区分 CoreBluetooth 物理链路、对象实例和 App 消息流。
- 不把协议推测写成 Tesla 官方行为。
- 优先实施可验证且不会引入安全回归的修改。

## 2. 复核依据

App 当前锁定依赖：

```text
TeslaBLEKeyKit
revision: d5da62c003ac6e2e0d8695f910957dd5708c82d7
```

关键源码：

```text
TeslaBLEKeyKit/Sources/TeslaBLEKeyKitBLE/BLEConnection.swift
TeslaBLEKey/Bluetooth/LegacyVCSECClient.swift
TeslaBLEKey/Model/VehicleController.swift
TeslaBLEKey/App/TeslaBLEKeyApp.swift
```

Apple 官方参考：

- Core Bluetooth Background Processing for iOS Apps
  https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
- `centralManager(_:willRestoreState:)`
  https://developer.apple.com/documentation/corebluetooth/cbcentralmanagerdelegate/centralmanager(_:willrestorestate:)

## 3. 结论摘要

| Gemini 建议 | 复核结论 | 优先级 |
|---|---|---:|
| AsyncStream 断开未 finish | 不成立，实际源码已经 finish | 无需按原建议修改 |
| 旧 responder 永久挂起并吞新消息 | 当前实现无直接证据，建议增加测试 | P2 |
| 必须改为单连接 Message Router | 证据不足，不能直接实施 | 研究项 |
| 双连接可能有车辆连接槽位/counter 风险 | 合理，需要实车证据 | P1/P2 |
| 引入严格恢复状态机 | 同意 | P1，若日志证明重入则 P0 |
| estimatedDistance 保持缺失 | 暂时同意，但语义仍需证据 | 研究项 |
| BLE 断开不主动锁车 | 同意 | 保持现状 |
| 启动时立即重建可恢复 Central | 同意 | 保持现状 |
| 后台依赖系统托管连接 | 同意 | 保持现状 |
| 进入后台前发送存活确认 | 不建议 | 不实施 |

## 4. AsyncStream 生命周期：Gemini 的 P0 判断不符合实际源码

Gemini 的判断是：

> BLE 断开时如果不显式调用 `continuation.finish()`，`iterator.next()` 会永久挂起，造成旧 Task 堆积和新消息被旧 Task 吞噬。

这个一般性风险描述本身是正确的，但当前锁定版本已经处理。

### 4.1 实际断开代码

`BLEConnection.centralManager(_:didDisconnectPeripheral:error:)`：

```swift
public func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
) {
    queue.async {
        for continuation in self.writeContinuations {
            continuation.resume(
                throwing: error ?? TeslaError.notConnected
            )
        }
        self.writeContinuations.removeAll()

        self.receiveContinuation?.finish()
        self.receiveContinuation = nil

        self.resumeConnect(
            with: error ?? TeslaError.notConnected
        )

        NotificationCenter.default.post(
            name: Self.didDisconnectNotification,
            object: self
        )
    }
}
```

### 4.2 主动关闭同样结束流

```swift
public func close() {
    queue.async {
        self.central?.stopScan()
        if let peripheral = self.peripheral {
            self.central?.cancelPeripheralConnection(peripheral)
        }

        self.receiveContinuation?.finish()
        self.receiveContinuation = nil
        // 释放等待中的连接与写入 continuation
    }
}
```

### 4.3 responder 的自然退出

```swift
while !Task.isCancelled,
      let message = await self.iterator.next() {
    // 处理认证请求
}
```

当 continuation 被 `finish()` 后，`iterator.next()` 返回 `nil`，循环结束。

恢复前控制器还会执行：

```swift
passiveKeyClient?.stopPassiveAuthenticationResponder()
passiveKeyClient = nil
passiveKeyOnline = false
```

因此当前生命周期为：

```text
BLE 断开
→ receiveContinuation.finish()
→ 旧 iterator 返回 nil
→ 旧 responder 循环结束
→ connect() 检测 continuation 为空
→ 创建新的 AsyncStream
→ 建立新的 LegacyVCSECClient
→ 新 iterator 开始监听
```

### 4.4 仍建议增强的地方

虽然原 P0 不成立，仍应增加：

- 流 generation ID。
- `responder.started`、`responder.cancelled`、`responder.ended` 诊断事件。
- 断开后旧 iterator 必须在限定时间内结束的测试。
- 重连后只有一个 responder 存活的测试。
- framer 解析错误后 stream 完成并能重建的测试。
- `BLEConnection` 析构或永久关闭时的统一终止测试。

复核结论：当前不是“未 finish”的 P0 缺陷，但缺少针对该生命周期的自动化证明。

## 5. 双连接与单连接路由：不能根据物理链路推导消息被吞

Gemini 的判断是：

> iOS 针对同一外设只维护一条物理链路，两个 CBPeripheral 会收到相同通知，所以两个客户端会争抢消息，必须改成单连接和 Message Router。

这段推导混合了三个层次：

```text
蓝牙控制器/Physical Link
CoreBluetooth CBCentralManager 与 CBPeripheral 实例
App 自己的 BLEFramer、AsyncStream 与协议消费者
```

即使底层无线控制器复用物理链路，也不能直接推出一个 Swift `AsyncStream` 会从另一个独立 `AsyncStream` 中取走消息。

### 5.1 当前两条连接各自独立

普通命令与被动钥匙分别拥有：

- 独立 `BLEConnection`。
- 独立 `CBCentralManager`。
- 独立 `CBPeripheral` 引用。
- 独立 delegate。
- 独立 TX/RX characteristic 引用。
- 独立 `BLEFramer`。
- 独立 `AsyncStream` 和 continuation。
- 独立 VCSEC client。

因此不存在两个业务消费者调用同一个 iterator 的直接代码路径。

如果 CoreBluetooth 把特征通知分别交给两个已订阅的 delegate，更可能是各对象收到各自回调，而不是旧 Task 从新连接的 App stream 中“偷走”消息。

### 5.2 Apple 允许多个 Central Manager

Apple 官方文档明确讨论一个 App 存在多个 Central Manager 的情况，并要求每个 restoration identifier 唯一。系统会对各 Central 保存：

- 正在扫描的服务。
- 正在连接或已经连接的外设。
- 已订阅的特征。

这证明“多个 Central 一定不受支持”并不成立，但不代表它自动证明 Tesla 双会话一定安全。

### 5.3 双连接真正的风险

值得调查的是：

1. Tesla 是否限制同时 GATT 连接数量。
2. 同一 Key ID 的两个 VCSEC 会话是否共享 counter 窗口。
3. 两条会话是否互相推动或使车辆拒绝 counter。
4. 后建立的会话是否让前一条 Phone Key 在车机上变灰。
5. 两个 Central 是否增加功耗和后台恢复复杂度。
6. 车辆是否向两个订阅者重复发送认证挑战。
7. 重复响应同一挑战时车辆如何处理。

这些风险需要：

- 实车时间线。
- CoreBluetooth delegate 日志。
- 每条连接独立 generation 标识。
- 协议消息类型计数。
- 条件允许时的 BLE/协议抓包。

### 5.4 单连接 Message Router 的成本

单连接路由在设计上可能更整洁，但需要解决：

- Session Info、Command Status、Vehicle Status 的请求关联。
- 相同消息类型的多个 pending request。
- AuthenticationRequest 的最高优先级抢占。
- VCSEC 与 Infotainment domain 的路由。
- 恢复时所有 pending continuation 的失效。
- 前台媒体轮询、车辆刷新、控制命令与门把手挑战并发。
- 进入后台后保留唯一连接，但释放所有非被动业务消费者。
- 一个错误消费者不能阻塞全局路由器。

贸然改成单连接可能重新引入项目过去已经遇到的“主动命令可用，但拉门挑战被其他读取者消耗”的问题。

复核结论：Message Router 可以作为中长期架构候选，但没有足够证据将其列为必须立即执行的 P0。

## 6. 恢复状态机：同意 Gemini 的方向

当前控制器使用多个状态变量：

```swift
passiveRecoveryInProgress
passiveKeyOnline
passiveConnection
passiveKeyClient
intentionalDisconnect
appIsBackgrounded
passiveReconnectTask
```

这些变量可以阻止部分重入，但组合状态不够直观。例如：

```text
连接存在，但特征未恢复
特征 ready，但 VCSEC 会话未建立
旧恢复任务正在返回，同时新 ready 事件到达
App 已进入后台，但前台重试刚刚开始
旧 responder 已结束，新 stream 尚未创建
```

建议引入：

```swift
enum PassiveKeyState: Equatable {
    case disabled
    case idle
    case waitingForVehicle
    case connecting
    case discoveringCharacteristics
    case establishingSession
    case listening
    case interrupted
    case restoring
    case failed(PassiveKeyFailure)
}
```

并为每次连接恢复分配单调递增的 generation：

```swift
struct PassiveKeyGeneration: Equatable {
    let value: UInt64
}
```

任何异步任务返回前必须验证：

```swift
guard generation == currentGeneration,
      passiveConnection === expectedConnection else {
    return
}
```

状态机应保证：

- 同时只有一个恢复任务。
- 旧 generation 不能覆盖新状态。
- `.listening` 状态收到重复 ready 不重建会话。
- intentional disconnect 不触发恢复。
- 车辆切换后旧车辆事件全部无效。
- 背景事件不启动无限软件重试。

复核结论：这是目前最值得实施的低风险升级。默认列为 P1；如果实车日志证明已经存在重复恢复或旧任务覆盖，可提升到 P0。

## 7. 45 秒恢复等待：需要更准确地描述风险

Gemini 将其描述成“`Task.sleep(45 秒)` 硬等待”，实际代码是：

```swift
try await link.connect(timeout: 45)
```

它等待连接与特征通知就绪，并不是无条件睡眠。

Apple 官方文档指出，App 因 BLE 事件在后台被唤醒后，通常只有约 10 秒处理相关任务，并应尽快返回。

风险在于：

```text
后台 BLE 事件唤醒 App
→ App 尝试完整连接/发现特征/VCSEC Session
→ 整个流程可能超过系统执行预算
→ iOS 再次挂起 App
→ 会话尚未进入 listening
```

但 Apple 同时说明：

- `connectPeripheral` 请求本身不会超时。
- 系统可以在 App 不运行时继续监控 pending connection。
- 外设重新可达时，系统可以重新启动 App 并投递连接回调。

当前依赖在应用层 connect 超时后仍保留 Central 和待处理连接，方向是合理的。

建议优化：

- CoreBluetooth pending connection 长期交给系统管理。
- 后台 ready 事件只执行必要的快速恢复。
- 为 VCSEC Session 设置短的单轮后台预算。
- 未完成时保留同一个 Central，等待下一系统事件。
- 区分“系统仍在连接”和“VCSEC 会话明确失败”。
- 不在后台运行每 15 秒的软件循环。

## 8. estimatedDistance：赞同保守处理，但 Gemini 的解释仍未被证明

Gemini 建议保持字段缺失，方向上与当前项目一致。

但它进一步声称：

> 车辆通过 B 柱、后视镜和中控多个天线三角定位，并把手机 estimatedDistance 纳入融合权重。

目前没有提供：

- Tesla Protobuf 字段定义。
- 官方客户端实现。
- 车辆端融合算法。
- 实车 PCAP。
- 字段单位。
- presence semantics。

因此这些描述只能标记为“合理推测”，不能当成官方事实。

当前实现只编码：

```text
AuthenticationResponse.authenticationLevel
```

没有编码 `estimatedDistance`。需要继续确认：

```text
字段缺失
显式写入 0
显式无效值
真实测距值
```

在车辆端是否具有不同语义。

明确同意以下结论：

- 不能把添加车辆页面的 RSSI 距离直接写入认证响应。
- 在不知道字段号、类型、单位和算法时不能猜测填值。
- 需要官方 schema、可信源码或实车抓包才能继续。

## 9. 离车锁车交由车辆：同意

当前 App 不在 BLE 断开时主动执行：

```swift
lock()
```

这是正确的安全边界，因为断开可能来自：

- 人体遮挡。
- 无线干扰。
- iOS 蓝牙栈切换。
- 车辆休眠。
- App 被系统挂起。
- 用户仍在车内或车旁。

盲目锁车可能造成误锁，而且 BLE 已断开时命令本身也未必能够送达。

Tesla 车辆端应结合 Phone Key、车门、座椅、挡位和其他车辆状态决定离车落锁。App 的职责是维持正确的 Phone Key 会话和认证响应，而不是用一个断开回调替代车辆安全逻辑。

## 10. Restoration ID 与托管连接：同意

当前做法：

- App 启动时立即重建带固定 restoration identifier 的 Central。
- 保存已知 `CBPeripheral.identifier`。
- 优先 `retrievePeripherals(withIdentifiers:)`。
- 对已知车辆提交系统托管连接。
- 不依赖后台名称扫描。
- 后台取消软件周期重试。

Apple 官方文档明确说明：

- 带 restoration identifier 才会获得状态保存。
- App 被系统重新启动后需要尽快用相同 ID 重建 Manager。
- 系统保存正在连接/已连接的 Peripheral 和特征订阅。
- `willRestoreState` 是恢复启动时最早的 delegate 回调之一。

因此这个方向符合官方机制。

## 11. “进入后台前主动存活确认”：不建议采用

Gemini 建议在进入后台前发送轻量存活确认。当前不建议实施：

- `scenePhase == .background` 已处于有限执行窗口。
- 可能与正在进行的命令、状态刷新或会话恢复竞争。
- 可能无意义唤醒车辆并增加功耗。
- 成功一次不能证明几分钟后连接仍健康。
- Apple 要求后台唤醒只执行与事件直接相关的必要工作。

更合理的策略：

- 前台期间保证 responder 已进入 `.listening`。
- 进入后台只释放普通命令连接。
- 保留可恢复 Phone Key Central。
- 记录状态与 generation，不额外发车辆命令。
- 后台依赖 CoreBluetooth delegate 事件。

## 12. 强制退出的表述需要保持谨慎

Gemini 声称强制退出后“只有用户点击图标才会恢复”。工程上应避免写成绝对定律。

可以确定的是：

- 用户强制退出通常表达了停止 App 的明确意图。
- 不能保证 CoreBluetooth 在此后重新启动 App。
- 产品不能承诺强退状态下的无感钥匙。

但不同 iOS 版本、系统事件和启动机制存在细节差异，文档应使用“系统不保证”而不是“绝对不可能”。

## 13. 对 Gemini 故障时间线判断的复核

### 情况 A：无 `ble.passive.proximity.ready`

可能原因：

- 已知 Peripheral 没有重新连接。
- Central 未正确恢复。
- 蓝牙关闭或权限变化。
- 车辆不在范围内。
- 车辆达到连接上限。
- App 被系统或用户终止后未获恢复机会。

不能只归结为“CoreBluetooth 恢复失败”。

### 情况 B：有 `proximity.ready`，无 `restore.ready`

较可能位于：

- VCSEC Session 请求未响应。
- ECDH/Session 数据不完整。
- counter 或 Key ID 被拒绝。
- App 在后台预算用完前未完成。
- 新 stream/characteristic 恢复不完整。

Gemini 的方向基本正确。

### 情况 C：有 `restore.ready`，无 `challenge.received`

可能原因：

- 车辆没有发挑战。
- 车辆认为手机不在对应门把手区域。
- 车辆端钥匙状态或车辆状态不允许。
- RX 特征通知没有继续投递。
- responder 已异常退出。
- 消息解析未识别挑战。

由于实际断开会 finish stream，不能优先断言是 AsyncStream 泄漏。

### 情况 D：有 challenge，但 `challenge.failed`

可能原因：

- Token 格式错误。
- Key ID 不匹配。
- counter 不兼容。
- AES-GCM/AAD 响应失败。
- BLE 写入失败。
- stream 或连接在响应期间中断。

Gemini 的密码学层判断合理，但还应包括传输中断。

### 情况 E：已 `challenge.responded.XXms`，车辆仍不解锁

`responded` 当前只证明 App 完成了 BLE 写入调用，不一定证明车辆接受响应。

可能原因：

- 车辆端拒绝认证。
- 车辆未确认 Command/Auth 状态。
- 门把手区域判断失败。
- 车辆安全状态不允许。
- 响应字段不完整。
- counter 虽已发送但被车辆判定无效。
- 未知的 `estimatedDistance` 语义。

建议增加车辆端确认或后续状态消息的诊断，而不是直接把 responded 等同于认证成功。

## 14. 修订后的优先级路线

### P0：只在有证据时实施

- 若日志证明同一时刻存在多个 responder，则修复 generation/任务所有权。
- 若日志证明双连接导致 counter 冲突、连接槽位失败或重复挑战，则评估单连接 Router。
- 若实车确认 AuthenticationResponse 缺少必要字段，则按准确 schema 修复。

当前不能仅凭 Gemini 的推测把这些直接认定为已发生 P0。

### P1：建议下一版实施

- 引入严格 `PassiveKeyState` 状态机。
- 为每次连接和恢复增加 generation token。
- 合并重复 `didDisconnect`、`didBecomeReady` 和前台恢复事件。
- 限制后台单轮协议恢复时间，不销毁系统托管连接。
- 车辆切换时使旧 generation 全部失效。

### P2：诊断与测试

- 记录 stream/responder 生命周期。
- 记录连接 generation。
- 记录恢复每个阶段耗时。
- 记录挑战接收、加密完成、BLE 写入完成和车辆确认阶段。
- 只记录 counter 差值，不记录完整 counter、Token 或密钥。
- 增加断开、恢复、重复 ready 和车辆切换的状态机测试。

### P3：体验

- UI 将“钥匙恢复中”细分为等待车辆、建立连接和建立安全会话。
- 诊断页给出安全且可执行的提示。
- 不在进入后台时额外发送车辆命令。

## 15. 建议 Gemini 继续回答的问题

请 Gemini 基于本文新增的实际源码证据继续评审：

1. 在 `didDisconnectPeripheral` 和 `close()` 都已经调用 `receiveContinuation.finish()` 后，是否仍坚持 AsyncStream 泄漏属于当前 P0？如果坚持，请指出具体仍存活的引用链和事件顺序。
2. 两个独立 `CBCentralManager`、delegate、BLEFramer 和 AsyncStream 如何发生“一个 Task 吞掉另一个 stream 消息”？请给出 CoreBluetooth 官方依据或可复现实验。
3. 如果两个连接收到的是通知副本，而不是竞争读取，真正风险是否应改为连接槽位、重复挑战和 counter 冲突？
4. 单连接 Router 如何关联多个相同类型的 VCSEC 响应，并保证 AuthenticationRequest 不被前台媒体/状态请求阻塞？
5. 单连接进入后台时，如何释放主动业务消费者但保留唯一 Phone Key 会话而不破坏 pending continuation？
6. `estimatedDistance` 的具体 schema、单位和 presence semantics 依据是什么？
7. 如何在 Apple 约 10 秒后台处理预算内恢复 VCSEC Session，同时保留长期系统托管连接？
8. 状态机应该部署在 App Controller、BLEConnection，还是两层各自维护并通过事件协调？

如果不能给出可靠依据，请将结论降级为“需要实车验证”，而不是“必须修改”。

## 16. 最终观点

Gemini 对状态机、车辆端离车锁车、Restoration ID 和避免伪后台保活的建议是正确的；对 AsyncStream 未结束的判断已被实际源码反驳；对双连接必须改成单连接的结论则缺乏足够证据。

下一步最稳妥的工程路线不是立即推翻双连接架构，而是先加入严格状态机、connection generation、完整的 stream/responder 生命周期测试和分阶段诊断。只有实车日志证明双连接造成连接槽位、重复挑战或 counter 冲突后，才值得承担单连接 Message Router 的高风险重构成本。
