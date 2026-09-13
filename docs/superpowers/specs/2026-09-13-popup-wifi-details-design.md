# Popup Wi‑Fi 详情与快捷设置设计

- 日期：2026-09-13
- 范围：Popup 的 Wi‑Fi 区域、当前 SSID 读取，以及系统 Wi‑Fi 设置入口

## 1. 背景

Popup 当前只显示 Wi‑Fi 的连接状态和信号格数，用户无法确认正在使用哪个网络，也不能从 Popup 直接进入系统 Wi‑Fi 设置。

macOS 15+ 的 CoreWLAN 只有在定位服务已启用且应用获得定位授权后，才允许读取当前 SSID。现有应用没有定位权限，因此本功能需要显式增加只用于读取 Wi‑Fi 名称的定位权限请求。

## 2. 目标

1. 在 Popup 的 Wi‑Fi 行显示当前连接的 SSID。
2. 在 Wi‑Fi 行提供一个可发现、可访问的系统设置快捷入口。
3. 首次启动时请求一次定位权限；已授权后无需重复请求。
4. 权限被拒绝、受限、Wi‑Fi 未连接或 SSID 不可读取时，Popup 保持可用并回落到现有状态文案。

## 3. 非目标

- 不实现 Wi‑Fi 扫描、网络切换或密码管理。
- 不改变菜单栏图标中的 Wi‑Fi 状态渲染。
- 不保存用户曾经连接过的网络名称。
- 不持续监听定位位置；定位权限仅用于满足 CoreWLAN 对 SSID 的系统授权要求。

## 4. 数据与权限设计

### 4.1 Wi‑Fi 状态模型

- `WiFiStatus` 增加 `ssid: String?`，默认值为 `nil`，保持现有构造调用兼容。
- `WiFiSystemReading` 增加 `ssid: String?`。
- `CoreWLANWiFiSystemReader` 从当前 `CWInterface` 读取 `ssid()`，空字符串或 `nil` 统一归一化为 `nil`。
- `WiFiMonitor` 在发布状态时携带归一化后的 SSID；状态为 `unavailable` 时沿用现有短暂保留策略，避免瞬时读取失败让名称闪烁。

### 4.2 定位授权

- 新增一个定位授权适配器，负责读取 `CLLocationManager.authorizationStatus` 并在 `.notDetermined` 时调用 `requestWhenInUseAuthorization()`。
- `WiFiMonitor.start()` 在启动监听时触发一次授权检查。
- 授权状态从 `.notDetermined` 变为已授权后，授权适配器通知 `WiFiMonitor` 立即刷新。
- 被拒绝或受限时不反复弹窗；后续仍可通过更新或重新打开 Popup 刷新，显示无 SSID 的回退文案。
- `Support/Info.plist` 增加 `NSLocationWhenInUseUsageDescription`，文案明确说明权限仅用于显示当前 Wi‑Fi 网络名称。

## 5. UI 设计

Popup 的 Wi‑Fi 区域保持现有紧凑单行布局：

- 标题：`Wi-Fi`。
- 副标题：SSID 可用时显示网络名；否则沿用 `StatusPresentation.wifiSubtitle` 的现有状态文案。
- 右侧：保留当前信号格数或状态值。
- 状态值右侧：增加齿轮图标按钮。
- 齿轮按钮使用 `打开 Wi‑Fi 设置` 的辅助功能标签和悬浮提示，视觉上保持次级样式。
- 点击后先关闭 Popup，再打开系统设置。

系统设置入口按顺序尝试：

1. `x-apple.systempreferences:com.apple.Network-Settings.extension`
2. `x-apple.systempreferences:com.apple.preference.network`

第一个成功打开的 URL 即停止尝试。

## 6. 可访问性

- 菜单栏状态项的 VoiceOver 摘要在有 SSID 时包含网络名称，例如 `Wi-Fi Office，3 格`。
- 无 SSID 时 VoiceOver 摘要与现有行为一致。
- 齿轮按钮必须有可读标签，不能只依赖图标含义；按钮命中区域不小于现有行内控件。
- 网络名使用尾部截断，避免长 SSID 挤压信号值和设置按钮。

## 7. 验收

- 首次启动且权限未决定时会请求一次定位权限。
- 授权后 Popup 的 Wi‑Fi 副标题显示当前 SSID，网络切换后名称随之更新。
- 拒绝权限、Wi‑Fi 关闭、未关联或 SSID 不可用时，Popup 不崩溃且显示现有状态回退文案。
- 点击齿轮按钮关闭 Popup，并打开系统网络设置。
- 现有测试全部通过；新增或更新的测试覆盖 SSID 归一化、状态呈现、授权回调后的刷新，以及系统设置 URL 回退顺序。
- Release app bundle 可构建、签名并启动。
