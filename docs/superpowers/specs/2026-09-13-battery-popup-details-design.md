# Popup 电池详情设计

- 日期：2026-09-13
- 范围：Status Trio popup 的电池状态、预计充满时间和电源设置快捷入口

## 1. 背景

Popup 当前只显示电池百分比和简短状态。用户无法直接看到电池是否已经充满、正在充电时还需要多久，也无法从电池区域进入系统电源设置。

参考项目 Stats 的 Battery 模块使用 IOPS 的 `kIOPSIsChargedKey` 和 `kIOPSTimeToFullChargeKey` 读取充满状态与预计充满时间。本设计只复用这两个公开数据来源，不引入 Stats 的完整仪表盘、电芯参数或进程排行。

## 2. 目标

1. 百分比与“电池”标题合并显示为 `电池 · 68%`，不再单独占据右侧列。
2. 状态副标题区分 `已充满`、`预计 … 充满`、`已连接电源`、`低电量模式`、`电池供电` 和 `无电池设备`。
3. 正在充电且系统提供时间时，直接显示 `预计 1 小时 25 分钟充满`；时间不可用时显示 `正在计算充满时间`。
4. 电池存在时，行尾提供齿轮按钮；点击后关闭 popup 并打开系统“电池”设置。
5. 保持现有 popup 的紧凑三行布局和视觉语言。

## 3. 非目标

- 不直接切换充电、低电量模式或其他电源设置。macOS 没有可供第三方应用稳定使用的公开控制 API。
- 不增加电池健康度、循环次数、温度、功率、电压或电芯容量。
- 不改变菜单栏图标、右键菜单或设置窗口。
- 不展示电池供电时的剩余使用时间。

## 4. 交互设计

采用“增强现有状态行”方案：

```text
▰  电池 · 68%                                      ⚙
   预计 1 小时 25 分钟充满
──────────────────────────────────────────────────────
```

- `电池 · 68%` 使用现有标题字号，百分比使用等宽数字，避免数值更新时抖动。
- 充电时副标题就是预计充满时间，不再额外显示“正在充电”。
- 已充满时显示 `已充满`，不显示计时。
- 已连接电源但未充电且未满时显示 `已连接电源`。
- 使用电池时显示 `电池供电`；低电量模式开启时显示 `低电量模式`。
- 无电池设备时显示 `无电池设备`，并隐藏齿轮按钮。
- 齿轮使用与 Wi-Fi 设置按钮相同的 plain icon-only 样式、24 pt 点击区域和无障碍标签 `打开电源设置`。

## 5. 数据模型与读取

### 5.1 `BatteryReading`

位置：`Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift`

新增字段：

- `isCharged: Bool = false`
- `timeToFullChargeMinutes: Int? = nil`

默认值让现有 `BatteryReading` 构造点无需为无关字段改写。`IOPSBatteryReader.parse` 从 IOPS 描述中读取：

- `kIOPSIsChargedKey`，缺失时回退 `false`
- `kIOPSTimeToFullChargeKey`，复用现有 `integerValue` 做 `Int` / `NSNumber` 容错

时间只在为正数时保留；`nil`、`0` 和负数统一视为未知，避免把 IOPS 的哨兵值显示成倒计时。

### 5.2 `BatteryStatus`

位置：`Sources/StatusTrioCore/Models/StatusSnapshot.swift`

新增字段：

- `isCharged: Bool`
- `timeToFullChargeMinutes: Int?`

提供带默认值的显式初始化方法：`isCharged` 默认 `false`，`timeToFullChargeMinutes` 默认 `nil`。这样现有图标测试和其他构造点无需为了无关字段全部改写。

`BatteryMonitor.refresh()` 的状态优先级为：

1. 电池不存在：`isPresent == false`，清空充电状态和时间。
2. 电池存在：保留 `isCharged`；只有 `isCharging == true` 且时间大于 0 时才写入 `timeToFullChargeMinutes`。

## 6. 呈现格式

`StatusPresentation` 增加一个纯格式化方法，用于将分钟转换为副标题文案：

| 输入 | 输出 |
| --- | --- |
| `nil` 或 `<= 0`，且正在充电 | `正在计算充满时间` |
| `1 ... 59` | `预计 N 分钟充满` |
| `60`、`120`、`180` 等整小时 | `预计 N 小时充满` |
| 其他 `>= 60` | `预计 N 小时 M 分钟充满` |

`batterySubtitle` 的状态优先级：

1. 无电池：`无电池设备`
2. `isCharged`：`已充满`
3. `isCharging`：按上表生成预计充满时间
4. `isLowPowerMode`：`低电量模式`
5. `isConnectedToPower`：`已连接电源`
6. 其他：`电池供电`

`isCharged` 与 `isCharging` 同时为真时显示 `已充满`，因为已经达到可拔电状态。

## 7. UI 与接线

### 7.1 `BatteryStatusView`

位置：`Sources/StatusTrioCore/UI/BatteryStatusView.swift`

新增独立 SwiftUI 组件：

- 输入 `BatteryStatus` 和 `onOpenBatterySettings: () -> Void`
- 左侧为现有电池图标
- 中间为标题 `电池 · N%` 和 `StatusPresentation.batterySubtitle`
- 右侧为设置齿轮
- `battery.isPresent == false` 时不显示齿轮
- 设置齿轮包含 `accessibilityLabel` 和 `help`

`StatusPopoverView` 用该组件替换原电池 `statusRow`，新增 `openBatterySettings` 回调，并删除替换后不再使用的通用 `statusRow` helper。

### 7.2 系统设置入口

`StatusBarController` 新增：

- `handleOpenBatterySettings`：先关闭 popover，再按顺序尝试打开系统设置 URL。
- `batterySettingsURLs`：
  1. `x-apple.systempreferences:com.apple.Battery-Settings.extension`
  2. `x-apple.systempreferences:com.apple.preference.battery`

URL 列表保持 `static` 以便测试回退顺序。第一个 URL 失败时继续尝试旧版 URL；全部失败时不显示错误弹窗，也不影响 popup 后续打开。

## 8. 测试

新增或更新以下测试：

- `BatteryMonitorTests`
  - IOPS 描述能解析 `isCharged` 和 `timeToFullChargeMinutes`
  - 缺失或非正时间转成 `nil`
  - 非充电状态不传递预计时间
  - 无电池状态清空时间
- `StatusPresentationTests`
  - 分钟、整小时、小时加分钟、未知时间的格式化
  - `无电池`、`已充满`、`预计 … 充满`、`低电量模式`、`已连接电源`、`电池供电` 的优先级
  - 无障碍摘要继续包含充电或充满状态
- `StatusMenuBuilderTests`
  - 电池设置 URL 回退顺序固定为 ExtensionKit URL 后接旧版 preference URL
- `StatusSnapshotTests`
  - 新字段在 placeholder 和缺失值下具有稳定默认值

## 9. 验收

- Popup 显示 `电池 · 68%`，没有单独的百分比列。
- 正在充电时直接显示 `预计 1 小时 25 分钟充满`；未知时间显示 `正在计算充满时间`。
- 已充满、已连接电源、低电量模式和电池供电均有准确文案。
- 点击齿轮关闭 popup，并打开系统“电池”设置。
- 无电池设备不显示齿轮，且不崩溃。
- 现有测试与新增测试全部通过。
- Release app bundle 可构建、签名并启动。
