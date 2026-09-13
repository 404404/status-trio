# 设置界面设计

- 日期：2026-09-13
- 范围：Status Trio 的设置界面，以及首个设置项「图标渲染范围」

## 1. 背景

菜单栏图标的渲染尺寸目前硬编码为 `StatusIconRenderer` 的默认值（28 pt）。popover 与右键菜单里各有一个禁用的「设置… · 即将推出」占位项，没有任何真实设置界面。

图标尺寸是纯个人偏好：机器与菜单栏高度不同，合适尺寸也不同。28 pt 是当前菜单栏下可接受的最大值，用户需要能自行往下调到 20 pt。

## 2. 目标

1. 提供原生设置界面，作为后续所有设置项的统一容器。
2. 第一个设置项为「图标渲染范围」，可选 20–32 pt，默认 28 pt。上限取 32 pt：菜单栏高度约 30–33 pt，图标墨迹约为画布尺寸的 94%，32 pt 是两种菜单栏高度下都不会裁切的务实上限。
3. 调整后立即作用于菜单栏图标，且跨启动持久化。
4. 两个入口都能打开设置界面：左键 popover 里的「设置…」与右键菜单里的「设置…」。

## 3. 非目标

- 不引入 SwiftUI `App` 场景或 `Settings` scene（本应用是 `NSApplication` + `AppDelegate`）。
- 不做快捷键绑定、全局快捷键或菜单栏主菜单。
- 不新增除图标尺寸之外的第二项设置。

## 4. 形态选择

| 方案 | 结论 |
| --- | --- |
| 独立设置窗口 | 采用。后续设置项变多不会撑高 popover，符合 macOS 习惯。 |
| popover 内联 | 不采用。选项增加后 popover 会过高。 |
| 右键菜单子菜单 | 不采用。不是「界面」形态。 |

## 5. 组件设计

### 5.1 `SettingsStore`

- 位置：`Sources/StatusTrioCore/Settings/SettingsStore.swift`
- `@MainActor final class SettingsStore: ObservableObject`
- `static let iconSizeRange: ClosedRange<Double> = 20...32`
- `static let defaultIconSize: Double = 28`
- `@Published var iconSize: Double`：写入时夹取到 `iconSizeRange`，并持久化到 `UserDefaults`（key `menuBarIconSize`）。
- `init(defaults: UserDefaults = .standard)`：读取已存值，非法或缺失时回落 `defaultIconSize`。可注入 `UserDefaults` 以便测试。
- 读取容错：非数字、非有限值（如 NaN/∞）一律回落默认值。

### 5.2 `SettingsWindowController`

- 位置：`Sources/StatusTrioCore/UI/SettingsWindowController.swift`
- 懒创建单个 `NSWindow`（`.titled` + `.closable`，不可缩放），内容为 `NSHostingView`/`NSHostingController` 包裹的 `SettingsView`。
- `show()`：`NSApp.activate()` 后 `makeKeyAndOrderFront`，保证 accessory app 的窗口能到前台。
- 窗口复用，不重复创建。

### 5.3 `SettingsView`

- 位置：`Sources/StatusTrioCore/UI/SettingsView.swift`
- 首个选项「图标渲染范围」：`Slider`（20–32，步进 1 pt）＋右侧实时读数（默认 28 pt）。
- 附带实时预览：复用 `StatusIconRenderer` 按当前尺寸渲染图标，拖动即可见效果；预览槽位固定 28 pt 宽以免布局跳动。
- 预览外观跟随 `colorScheme`（`.aqua` / `.darkAqua`），回退到 `NSApp.effectiveAppearance`。
- 无障碍：滑块带 label「图标渲染范围」与当前值，预览对 VoiceOver 隐藏。

### 5.4 接线

- `StatusIconRenderer.image(snapshot:size:appearance:)` 的 `size` 改为必填，删除 `baseSize`：默认值只由 `SettingsStore.defaultIconSize` 定义，避免两处常量漂移。
- `SettingsStore` 成为尺寸的唯一来源；`StatusBarController` 注入 `SettingsStore`，订阅 `$iconSize`，变化即用新尺寸重渲染状态项。
- `StatusBarController` 增加 `openSettings` 回调：popover 的「设置…」按钮与右键菜单项都调用它，调用前先关闭 popover。
- `StatusMenuBuilder.makeMenu(version:settingsTarget:settingsAction:)` 接收 settings 项的目标与 action，动态启用该项。
- `AppEnvironment` 组装 `SettingsStore` 与 `SettingsWindowController`，并持有窗口控制器以保证生命周期。

## 6. 验收

- 设置窗口可从 popover 与右键菜单两处打开，且只存在一个窗口实例。
- 滑块范围 20–32 pt，默认 28 pt；拖动时菜单栏图标立即改变尺寸。
- 退出并重启应用后，尺寸保持上次设置值。
- 越界或非法持久化值不会导致异常尺寸，回落/夹取到合法值。
- 现有测试全部通过，并新增 `SettingsStore` 测试；Release app bundle 可构建、签名并启动。
