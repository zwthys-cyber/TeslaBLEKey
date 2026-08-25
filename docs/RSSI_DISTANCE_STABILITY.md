# Tesla BLE 附近车辆距离稳定性升级说明

> 项目：小特蓝牙钥匙  
> 版本：v2.3.2（Build 232）  
> 平台：iOS 17 / SwiftUI / CoreBluetooth  
> 文档用途：供技术评审、算法复核及 Google Gemini 分析

## 1. 升级目标

旧版本在“添加车辆”页面显示附近 Tesla 时，即使手机和车辆都没有移动，距离也可能在短时间内明显跳动，例如：

```text
0.8 米 → 2.7 米 → 1.1 米 → 5.4 米
```

本次升级目标如下：

- 降低 RSSI 与估算距离的视觉抖动。
- 提高多辆车远近排序的稳定性。
- 让默认选择的最近车辆更加可信。
- 去除 BLE 无法支撑的厘米级、小数级“伪精度”。
- 车辆离开范围后及时从候选列表消失。
- 车辆重新出现时不继承已经过期的 RSSI 样本。

## 2. 技术边界

App 无法从 Tesla BLE 广播直接获得真实物理距离，主要能够取得：

- RSSI：iPhone 接收到的蓝牙信号强度。
- Tx Power：广播包可能提供的参考发射功率。

内部使用路径损耗模型估算距离：

```swift
var estimatedDistance: Double {
    let calibratedPower = txPower ?? -59
    let meters = pow(10, Double(calibratedPower - rssi) / 22.0)
    return min(max(meters, 0.05), 99)
}
```

RSSI 会受到手机方向、人体遮挡、车身金属、天线位置、反射、多径传播、Wi-Fi 干扰、设备型号和车辆发射功率等因素影响。RSSI 与估算距离又是指数关系，因此几 dBm 的变化就可能造成较大的距离变化。

普通 BLE RSSI 只能用于“接近程度估算”，不能提供类似 UWB、双向飞行时间测距或卷尺测量的精度。

## 3. 旧版本方案

旧版本只使用当前 RSSI 与上一轮结果进行简单指数移动平均：

```swift
let smoothedRSSI = previousRSSI.map {
    Int(Double($0) * 0.7 + Double(currentRSSI) * 0.3)
} ?? currentRSSI
```

即：

```text
新 RSSI = 上一轮结果 × 70% + 当前原始 RSSI × 30%
```

主要问题：

1. 单个异常广播仍以 30% 权重进入结果。
2. 每个广播包都可能触发距离文字与 SwiftUI 列表更新。
3. 没有微小变化死区和单次跳变限制。
4. 广播包缺失 Tx Power 时可能回退到默认值并产生距离跳变。
5. 页面显示 `0.09 米`、`1.7 米` 等 BLE 无法证明的精度。

## 4. v2.3.1 基线数据处理流程

```text
原始 RSSI
    ↓
每辆车独立的最近 7 个样本窗口
    ↓
中位数异常值过滤
    ↓
指数平滑
    ↓
±1 dBm 微小变化死区
    ↓
单次最多 ±3 dBm 跳变限幅
    ↓
稳定 RSSI
    ↓
连续距离估算（用于排序）
    ↓
合理的米级量化（用于显示）
```

## 5. 每辆车独立保存最近 7 个样本

```swift
private var recentRSSISamples: [UUID: [Int]] = [:]
```

收到广播时：

```swift
var samples = recentRSSISamples[peripheral.identifier] ?? []
samples.append(RSSI.intValue)
samples = Array(samples.suffix(7))
recentRSSISamples[peripheral.identifier] = samples
```

设计理由：

- 奇数窗口可以得到明确中位数。
- 7 个样本足以抵抗少量异常值。
- 不会引入过长的跟随延迟。
- 每辆车以 CoreBluetooth 外设 UUID 隔离，不会互相污染。
- 计算量和内存开销可以忽略。

## 6. 中位数过滤

```swift
let sorted = samples.sorted()
let median = sorted[sorted.count / 2]
```

例如：

```text
原始样本：-61, -60, -59, -28, -60
排序结果：-61, -60, -60, -59, -28
中位数：  -60
```

异常的 `-28 dBm` 不会显著改变结果。如果使用算术平均值，结果会被异常值拉到约 `-53.6 dBm`。中位数更适合过滤 RSSI 的突发尖峰。

## 7. 指数平滑

中位数不会被直接输出，而是与上一轮稳定结果融合：

```swift
let blended = Int(
    (Double(previous) * 0.82 + Double(median) * 0.18).rounded()
)
```

当前参数：

```text
上一轮稳定结果：82%
当前窗口中位数：18%
```

与旧版的 `70% / 30%` 相比，新版更偏向稳定，但持续靠近或远离时仍会逐步跟随。

## 8. 微小变化死区

```swift
if abs(blended - previous) <= 1 {
    return previous
}
```

当计算结果变化不超过 `1 dBm` 时保持原值，避免没有实际判断价值的微小波动造成：

- 距离文字持续刷新。
- 多车排序来回变化。
- 默认选择在两辆车之间跳动。
- SwiftUI 产生无意义的视图更新。

## 9. 单次跳变限幅

```swift
return min(max(blended, previous - 3), previous + 3)
```

单次更新最多改变 `±3 dBm`。例如上一轮为 `-70 dBm`，新窗口长期处于约 `-48 dBm`，第一轮最多更新到 `-67 dBm`，后续再逐步变化：

```text
-70 → -67 → -64 → -61 → -58 → …
```

它不会永久锁死信号，只会阻止一次广播造成大跨度跳变。

## 10. v2.3.1 基线稳定算法

```swift
static func stabilizedRSSI(samples: [Int], previous: Int?) -> Int {
    guard !samples.isEmpty else { return previous ?? -100 }

    let sorted = samples.sorted()
    let median = sorted[sorted.count / 2]
    guard let previous else { return median }

    let blended = Int(
        (Double(previous) * 0.82 + Double(median) * 0.18).rounded()
    )

    if abs(blended - previous) <= 1 {
        return previous
    }

    return min(max(blended, previous - 3), previous + 3)
}
```

## 11. Tx Power 缺失处理

新版在当前广播包没有 Tx Power 时，继承同一车辆上一次有效值：

```swift
txPower: advertisedTxPower ?? previous?.txPower
```

只有从未获得有效 Tx Power 时，距离模型才使用默认 `-59 dBm`。这样可以避免部分广播帧缺字段造成距离突然变化。

## 12. 距离显示升级

旧版可能显示：

```text
约 0.09 米
约 0.74 米
约 1.7 米
约 4.3 米
```

新版显示：

```text
1 米内
约 2 米
约 4 米
约 15 米
约 40 米
```

实现规则：

```swift
var distanceLabel: String {
    switch estimatedDistance {
    case ..<1:
        "1 米内"
    case ..<10:
        "约 \(max(Int(estimatedDistance.rounded()), 1)) 米"
    case ..<30:
        "约 \(Int((estimatedDistance / 5).rounded()) * 5) 米"
    default:
        "约 \(Int((estimatedDistance / 10).rounded()) * 10) 米"
    }
}
```

| 内部估算距离 | 用户界面显示 |
|---:|---:|
| 小于 1 米 | 1 米内 |
| 1–10 米 | 四舍五入到整数米 |
| 10–30 米 | 四舍五入到 5 米刻度 |
| 30 米以上 | 四舍五入到 10 米刻度 |

## 13. 显示精度与排序精度分离

界面文字进行了合理量化，但默认选择最近车辆时仍使用内部连续浮点距离：

```swift
static func isNearer(_ lhs: NearbyTesla, than rhs: NearbyTesla) -> Bool {
    if abs(lhs.estimatedDistance - rhs.estimatedDistance) > 0.001 {
        return lhs.estimatedDistance < rhs.estimatedDistance
    }
    if lhs.rssi != rhs.rssi {
        return lhs.rssi > rhs.rssi
    }
    return lhs.peripheralName.localizedStandardCompare(rhs.peripheralName)
        == .orderedAscending
}
```

因此：

- 用户不会看到虚假的小数精度。
- 内部排序不会因为整数显示而丢失分辨率。
- 距离相近时继续比较稳定 RSSI。
- 最后用车辆标识提供确定性排序。

## 14. 离开范围与样本清理

每辆车保存最后一次广播时间，扫描期间每秒维护一次列表。连续约 6 秒没有收到广播的车辆会被移除：

```swift
private static let advertisementExpiry: TimeInterval = 6
```

```swift
static func freshVehicles(
    from vehicles: [UUID: NearbyTesla],
    now: Date,
    maximumAge: TimeInterval = advertisementExpiry
) -> [UUID: NearbyTesla] {
    vehicles.filter {
        now.timeIntervalSince($0.value.lastSeen) <= maximumAge
    }
}
```

车辆移除时，对应滤波样本同步删除：

```swift
recentRSSISamples = recentRSSISamples.filter {
    vehiclesByID[$0.key] != nil
}
```

效果：

- 离开范围的车辆不会长期显示旧距离。
- 已经消失的选中车辆会从添加页取消选择。
- 车辆重新进入范围后从新样本开始计算。
- 不会继承离开前的历史 RSSI。

## 15. 前后版本对比

| 项目 | 旧版本 | v2.3.1 |
|---|---|---|
| RSSI 数据 | 当前值与上一轮结果 | 每车最近 7 个原始样本 |
| 异常值处理 | 无专门处理 | 中位数过滤 |
| 平滑权重 | 旧值 70%，新值 30% | 旧值 82%，中位数 18% |
| 微小变化 | 每次更新 | ±1 dBm 内保持原值 |
| 瞬时跳变 | 无限制 | 单次最多 ±3 dBm |
| Tx Power 缺失 | 可能回退默认值 | 继承该车上次有效值 |
| 一米内显示 | 两位小数 | “1 米内” |
| 十米内显示 | 一位小数 | 整数米 |
| 较远距离 | 整数米 | 5 米或 10 米刻度 |
| 内部排序 | 简单平滑距离 | 稳定 RSSI 的连续距离 |
| 离开范围 | 曾保留旧结果 | 约 6 秒自动移除 |
| 多车隔离 | 基础隔离 | 每辆车独立滤波窗口 |

## 16. 自动化回归测试

### 16.1 单次异常尖峰

```swift
XCTAssertEqual(
    NearbyTeslaScanner.stabilizedRSSI(
        samples: [-61, -60, -59, -28, -60],
        previous: -60
    ),
    -60
)
```

验证单个异常强信号不会改变稳定结果。

### 16.2 持续靠近与单次限幅

```swift
XCTAssertEqual(
    NearbyTeslaScanner.stabilizedRSSI(
        samples: [-49, -48, -47, -48, -49],
        previous: -70
    ),
    -67
)
```

验证持续增强的信号能够被识别，但单次最多变化 `3 dBm`。

### 16.3 过期车辆移除

构造一辆 2 秒前广播的车辆和一辆 7 秒前广播的车辆，清理后只保留前者。

### 16.4 显示精度

验证极近车辆显示“1 米内”，其他距离标签不再包含小数点。

## 17. 实际体验预期

原始 RSSI：

```text
-60, -61, -58, -62, -35, -60, -59
```

旧版距离可能表现为：

```text
约 2.0 米 → 约 2.2 米 → 约 1.7 米 → 约 2.4 米
→ 约 0.3 米 → 约 0.6 米 → 约 0.9 米
```

新版更接近：

```text
约 2 米 → 约 2 米 → 约 2 米 → 约 2 米
```

当用户持续靠近车辆时，距离会逐步变化：

```text
约 8 米 → 约 7 米 → 约 6 米 → 约 5 米
→ 约 4 米 → 约 3 米 → 约 2 米 → 1 米内
```

## 18. 当前参数

```text
样本窗口：7
上一轮结果权重：82%
新中位数权重：18%
微小变化死区：±1 dBm
单次最大变化：±3 dBm
车辆过期时间：6 秒
维护周期：1 秒
```

这些参数偏向稳定性。代价是用户真实移动后，显示会有少量跟随延迟。

## 19. 方案优点与限制

### 优点

- 不需要 Tesla 账号、网络或 Fleet API。
- 不需要位置权限和额外硬件。
- 兼容现有 Tesla BLE 广播。
- 多车辆独立滤波。
- 显著降低异常尖峰和距离抖动。
- 保留内部排序精度。
- 不再用小数制造无法证明的精确感。

### 限制

- 无法保证显示距离等于真实卷尺距离。
- 手机放入口袋、隔着人体或车身时仍会存在系统性偏差。
- 不同 iPhone、Tesla 车型和天线位置可能有不同表现。
- 滤波会引入少量响应延迟。
- 要实现真正精确测距，通常需要 UWB、Nearby Interaction、双向飞行时间测距或车辆端直接提供距离信息。

## 20. 当前发布与验证状态

```text
版本：v2.3.2
Build：232
```

GitHub Actions 已通过：

- Tesla 协议与密码学测试。
- iOS App 回归测试。
- Xcode 26 Swift Package 依赖解析。
- iPhone Release 无签名编译。
- TrollStore IPA 打包与上传。

发布地址：  
https://github.com/zwthys-cyber/TeslaBLEKey/releases/tag/v2.3.2

## 21. 建议评审问题

可请 Google Gemini 重点评估：

1. 七样本中位数与 `82% / 18%` 平滑组合是否过度平滑。
2. `±1 dBm` 死区与单次 `±3 dBm` 限幅是否适合 Tesla 广播频率。
3. 是否值得改用 Hampel filter、Kalman filter 或分位数滤波。
4. 多车排序是否应增加更强的迟滞，避免两辆距离接近时交换顺序。
5. 6 秒过期阈值在车辆休眠或广播间隔变化时是否合理。
6. 是否应按车型、iPhone 型号或实车标定 Tx Power/path-loss exponent。
7. 是否应将“距离”改称“接近程度”，进一步降低用户对物理精度的误解。

## 22. v2.3.2 评审后升级

根据外部技术评审，滤波进一步升级为方向相关的自适应 EMA：明显靠近使用 38% 新样本权重并允许单次最多增强 6 dBm；明显远离使用 14% 权重并维持单次最多减弱 3 dBm。样本不足 5 个时使用窗口中位数快速冷启动，窗口同时限制为最近 7 个样本与最近 4 秒。

多车辆不再直接用带百分比迟滞的比较闭包排序，以免破坏严格弱序关系。扫描器维护有状态主候选，新挑战者只有在比当前候选近 20% 且至少拉开约 0.8 米时才取代首位，其余车辆仍使用确定性距离排序。RSSI 与估算距离只服务添加车辆 UI，不介入 VCSEC Phone Key 拉门认证。

## 23. 一句话总结

v2.3.2 在七样本中位数基础上加入四秒时间窗、快速冷启动、方向相关自适应 EMA、快进慢出限幅和有状态多车主候选迟滞，目标是提供稳定且响应及时的附近车辆选择体验，而不是伪装成精密测距仪。
