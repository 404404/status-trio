# Popup Wi‑Fi 详情与快捷设置设计

- 日期：2026-09-13
- 范围：Popup 的 Wi‑Fi 区域、当前 SSID 读取，以及系统 Wi‑Fi 设置入口

## 1. 背景

Popup 当前只显示 Wi‑Fi 的连接状态和信号格数，用户无法确认正在使用哪个网络，也不能从 Popup 直接进入系统 Wi‑Fi 设置。

macOS 15+ 的 CoreWLAN 只有在定位服务已启用且应用获得定位授权后，才允许读取当前 SSID。为了避免应用在首次启动时主动索取与核心功能无关的权限，名称读取采用用户触发的按需授权流程；未授权时应用的其他功能保持完整可用。

## 2. 目标

1. 用户主动授权后，在 Popup 的 Wi‑Fi 行显示当前连接的 SSID。
2. 未授权时，仅在实际需要展示名称且当前已有 Wi‑Fi 连接的情况下显示可点击的名称占位入口。
3. 用户点击占位入口后才请求定位权限；应用启动时不自动请求。
4. 权限被拒绝、受限、Wi‑Fi 未连接或 SSID 不可读取时，Popup 保持可用并回落到现有状态文案。
5. 在 Wi‑Fi 行提供一个可发现、可访问的系统设置快捷入口。

## 3. 非目标

- 不默认请求定位权限，不在设置页或启动流程中引导授权。
- 不实现 Wi‑Fi 扫描、网络切换或密码管理。
- 不改变菜单栏图标中的 Wi‑Fi 状态渲染。
- 不保存用户曾经连接过的网络名称。
- 不持续监听定位位置；定位权限仅用于满足 CoreWLAN 对 SSID 的系统授权要求。

## 4. 数据与权限设计

### 4.1 Wi‑Fi 状态模型

- `WiFiStatus` 增加 `ssid: String?`，默认值为 `nil`，保持现有构造调用兼容。
- `WiFiStatus` 增加名称授权状态，用于区分“尚未询问”“已授权”“已拒绝”和“受限”，默认值为尚未询问。
- `WiFiSystemReading` 增加 `ssid: String?`。
- `CoreWLANWiFiSystemReader` 从当前 `CWInterface` 读取 `ssid()`，空字符串或 `nil` 统一归一化为 `nil`。
- `WiFiMonitor` 在发布状态时携带归一化后的 SSID 与当前授权状态；状态为 `unavailable` 时沿用现有短暂保留策略，避免瞬时读取失败让名称闪烁。

### 4.2 按需定位授权

- 新增一个定位授权适配器，负责读取 `CLLocationManager.authorizationStatus`，并只在用户触发时调用 `requestWhenInUseAuthorization()`。
- `WiFiMonitor.start()` 不请求权限，只读取并发布当前授权状态。
- Popup 中的名称占位入口调用 `SystemStatusStore`，再转发给 `WiFiMonitor`；仅当状态为尚未询问时发起系统权限请求。
- 授权状态变为已授权后，授权适配器通知 `WiFiMonitor` 立即刷新并发布 SSID。
- 权限为已拒绝或受限时不反复弹窗；Popup 改为提供“去设置中允许定位”的操作入口。
- `Support/Info.plist` 增加 `NSLocationWhenInUseUsageDescription`，文案明确说明权限仅用于显示当前 Wi‑Fi 网络名称。
- `README` 中原有“无定位权限”的技术基线更新为“仅在用户主动显示 Wi‑Fi 名称时请求可选定位权限”。

## 5. UI 设计

Popup 的 Wi‑Fi 区域保持现有紧凑单行布局：

- 标题：`Wi-Fi`。
- 副标题按以下优先级显示：
  1. SSID 可用时显示网络名。
  2. 当前 Wi‑Fi 已连接、但授权状态为尚未询问时，显示链接样式按钮“点击显示 Wi‑Fi 名称”。
  3. 当前 Wi‑Fi 已连接、但权限被拒绝或受限时，显示链接样式按钮“去设置中允许定位”。
  4. Wi‑Fi 未连接、关闭、不可用或已授权但无法读取名称时，沿用现有状态回退文案。
- 副标题中的按钮命中区域不小于现有行内控件，并使用明确的辅助功能标签。
- 右侧保留当前信号格数或状态值。
- 状态值右侧增加齿轮图标按钮，使用“打开 Wi‑Fi 设置”的辅助功能标签和悬浮提示。
- 点击齿轮按钮后先关闭 Popup，再打开系统网络设置。

系统网络设置入口按顺序尝试：

1. `x-apple.systempreferences:com.apple.Network-Settings.extension`
2. `x-apple.systempreferences:com.apple.preference.network`

第一个成功打开的 URL 即停止尝试。

定位权限被拒绝时，Popup 的操作入口关闭 Popup 后打开系统“隐私与安全性 > 定位服务”设置。

## 6. 可访问性

- 菜单栏状态项的 VoiceOver 摘要在有 SSID 时包含网络名称，例如 `Wi-Fi Office，3 格`。
- 无 SSID 时 VoiceOver 摘要与现有行为一致。
- 名称授权入口和设置齿轮按钮必须有可读标签，不能只依赖图标或文案点击区域。
- 网络名使用尾部截断，避免长 SSID 挤压信号值和设置按钮。

## 7. 验收

- 应用首次启动时不会请求定位权限。
- 已连接且尚未询问权限时，Popup 显示“点击显示 Wi‑Fi 名称”，点击后才出现系统权限提示。
- 授权后 Popup 的 Wi‑Fi 副标题显示当前 SSID，网络切换后名称随之更新。
- 拒绝权限后不再重复弹出权限提示，Popup 显示“去设置中允许定位”，点击后打开系统定位设置。
- Wi‑Fi 关闭、未关联、不可用或 SSID 不可读取时，Popup 不崩溃且显示现有状态回退文案。
- 点击齿轮按钮关闭 Popup，并打开系统网络设置。
- 现有测试全部通过；新增或更新的测试覆盖 SSID 归一化、按需授权、拒绝后的状态、状态呈现，以及系统设置 URL 回退顺序。
- Release app bundle 可构建、签名并启动。
