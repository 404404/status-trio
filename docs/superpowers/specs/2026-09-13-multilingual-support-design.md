# 多语言支持设计

- 日期：2026-09-13
- 范围：Status Trio 的界面文案、设置语言选择、运行时切换、系统权限文案与本地化验证
- 状态：设计已确认，待实现

## 1. 背景

当前应用的用户可见文案主要硬编码在 Swift 源码中，默认使用简体中文，少量数据层回退文案也直接写死中文。应用没有语言设置，无法跟随 macOS 的系统语言，也无法由用户覆盖语言。

首版需要支持 12 种常用语言，并允许用户在设置页选择“跟随系统”或某个固定语言。语言切换必须立即作用于 SwiftUI 界面、AppKit 菜单、窗口标题、帮助文案和无障碍文案，不要求重启应用。

## 2. 目标

1. 支持以下 12 种语言：

| 语言 | BCP-47 标识 | 本地化目录 |
| --- | --- | --- |
| 简体中文 | `zh-Hans` | `zh-Hans.lproj` |
| 繁体中文 | `zh-Hant` | `zh-Hant.lproj` |
| 英语 | `en` | `en.lproj` |
| 日语 | `ja` | `ja.lproj` |
| 韩语 | `ko` | `ko.lproj` |
| 西班牙语 | `es` | `es.lproj` |
| 法语 | `fr` | `fr.lproj` |
| 德语 | `de` | `de.lproj` |
| 意大利语 | `it` | `it.lproj` |
| 巴西葡萄牙语 | `pt-BR` | `pt-BR.lproj` |
| 俄语 | `ru` | `ru.lproj` |
| 阿拉伯语 | `ar` | `ar.lproj` |

2. 设置页提供语言选择，选项为“跟随系统”加上述 12 种语言。
3. 选择保存到 `UserDefaults`，应用重启后保持。
4. 语言变化立即刷新界面，无需重启。
5. 系统语言为中文时按地区与脚本正确区分简繁中文；其他语言无法匹配时回退英语。
6. 阿拉伯语使用从右到左布局。
7. 所有应用自有用户可见文案均可本地化；系统权限弹窗使用 `InfoPlist.strings` 提供译文。

## 3. 非目标

- 不增加设计表中 12 种语言之外的语言。
- 不引入在线下载语言包或运行时更新翻译。
- 不为英语、西班牙语、法语、德语等增加地区变体；本版本只提供表中列出的语言标识。
- 不翻译 Wi-Fi SSID、音频设备名称、系统设置页名称等外部或系统提供的内容。
- 不改变现有设置项的名称、范围或业务行为，只迁移文案并新增语言选择。
- 不把 macOS 定位授权弹窗改造成应用内弹窗。

## 4. 方案选择

| 方案 | 结论 |
| --- | --- |
| `.lproj` 资源 + 自定义 `Localization` 服务 | 采用。符合 Apple 本地化格式，可手动选择 bundle，并支持立即刷新。 |
| String Catalog + 修改 `AppleLanguages` 后重启 | 不采用。实现较小，但不满足立即刷新要求。 |
| Swift 源码内翻译字典 | 不采用。格式格式不标准，翻译维护、键完整性检查和后续扩展成本高。 |

核心方案是为每种语言建立标准 `.lproj/Localizable.strings`，由 `Localization` 根据系统偏好或手动选择加载对应语言的 bundle。视图和 AppKit 构建器不直接调用主 bundle，而是调用 `Localization.string(_:)`，从而避免受进程启动语言限制。

## 5. 组件设计

### 5.1 `AppLanguage`

新增 `Sources/StatusTrioCore/Localization/AppLanguage.swift`。

- `AppLanguage` 是 `String` 枚举，值为表中的 BCP-47 标识。
- 实现 `CaseIterable`、`Identifiable` 和 `Sendable`。
- 提供稳定的本地名称，例如英语显示 `English`，简体中文显示 `简体中文`，巴西葡萄牙语显示 `Português (Brasil)`。这些名称在所有界面中保持不变，便于用户识别。
- `layoutDirection` 对阿拉伯语返回从右到左，其余语言返回从左到右。
- `locale` 使用当前语言标识创建，供数字和格式参数使用。

### 5.2 `Localization`

新增 `Sources/StatusTrioCore/Localization/Localization.swift`。

- `@MainActor final class Localization: ObservableObject`，与现有 `SettingsStore` 的 Combine 风格保持一致。
- `enum LanguagePreference: Equatable` 表示 `.system` 或 `.language(AppLanguage)`。
- `@Published private(set) var resolvedLanguage: AppLanguage`：当前实际使用的语言。
- `@Published private(set) var preference: LanguagePreference`：当前设置。
- `setPreference(_:)` 更新并持久化设置；传入 `.system` 时删除持久化键。
- `init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages)` 允许测试注入系统语言列表。
- 持久化键为 `appLanguage`。值是 `AppLanguage.rawValue`；缺失、非法或不再是支持语言的旧值一律回退 `.system`。
- 系统语言解析顺序：
  1. 按 `preferredLanguages` 顺序寻找完全匹配。
  2. `zh-CN`、`zh-SG`、`zh-Hans-*` 等匹配 `zh-Hans`。
  3. `zh-TW`、`zh-HK`、`zh-MO`、`zh-Hant-*` 等匹配 `zh-Hant`。
  4. 其他语言使用去掉地区后的基础标识匹配。
  5. 没有匹配时使用 `en`。
- `string(_ key: LocalizationKey) -> String` 从当前语言 bundle 查找文案。
- `format(_ key: LocalizationKey, _ arguments: CVarArg...) -> String` 使用当前语言 locale 格式化参数。
- 如果某个语言 bundle 或键缺失，先回退英语 bundle；英语也缺失时返回稳定的 key 字符串，便于测试和定位。
- 监听 `NSLocale.currentLocaleDidChangeNotification`，在系统语言变化通知到达且当前为 `.system` 时重新解析语言。

### 5.3 `LocalizationKey`

新增 `Sources/StatusTrioCore/Localization/LocalizationKey.swift`。

- `LocalizationKey` 是 `String` 枚举，并实现 `CaseIterable`。
- 键采用稳定命名空间，例如：
  - `menu.settings`
  - `menu.quit`
  - `settings.title`
  - `settings.language`
  - `settings.language.followSystem`
  - `battery.title`
  - `battery.state.charging`
  - `wifi.state.connected`
  - `volume.title`
  - `accessibility.status`
- 代码只通过枚举引用键，避免散落字符串和拼写错误。
- `LocalizationKey.allCases` 用于自动化检查 12 个翻译文件是否覆盖全部键。

### 5.4 资源文件

新增目录：

```text
Sources/StatusTrioCore/Resources/
  en.lproj/Localizable.strings
  zh-Hans.lproj/Localizable.strings
  zh-Hant.lproj/Localizable.strings
  ja.lproj/Localizable.strings
  ko.lproj/Localizable.strings
  es.lproj/Localizable.strings
  fr.lproj/Localizable.strings
  de.lproj/Localizable.strings
  it.lproj/Localizable.strings
  pt-BR.lproj/Localizable.strings
  ru.lproj/Localizable.strings
  ar.lproj/Localizable.strings
```

- `Package.swift` 的 `StatusTrioCore` target 增加 `resources: [.process("Resources")]`。
- 文件使用 UTF-8 `.strings` 格式。
- 所有语言必须包含相同的非空键集合。
- 数值文案使用 `%d` 或 `%@`，并采用不依赖复数形态的中性单位表达，例如 `%d h %d min`、`%d 格`；避免在俄语、阿拉伯语等语言中产生错误的复数形式。
- 不通过拼接翻译片段构造句子；需要多个参数时使用完整的带占位符格式串。

### 5.5 系统权限文案

为 12 种语言增加 `InfoPlist.strings`，至少覆盖 `NSLocationWhenInUseUsageDescription`，用于 macOS 定位授权弹窗。

- 开发文件位于本地化资源目录中，作为翻译源。
- `scripts/build-app.sh` 创建 `Contents/Resources` 后，把每个 `<language>.lproj/InfoPlist.strings` 复制到 App bundle 对应目录。
- macOS 权限弹窗始终按系统语言选择译文，不受应用内手动语言选择影响。应用内其他文案仍按用户选择立即刷新。

### 5.6 SwiftUI 接线

- `AppEnvironment` 创建并持有一个 `Localization`，与 `SettingsStore` 一起注入界面。
- `SettingsView` 增加“语言”区域，使用原生 `Picker`：
  - 第一项为 `.system`，显示“跟随系统”。
  - 后续为 12 种语言，显示原生语言名。
  - 辅助说明文案说明变更立即生效。
- `SettingsWindowController` 接收 `Localization`，将其注入 `SettingsView`，并订阅 `resolvedLanguage` 更新窗口标题和内容视图布局方向。
- `StatusBarController` 接收 `Localization`，将其注入 popover 的 SwiftUI 环境；订阅 `resolvedLanguage` 后立即重算状态项的无障碍 label/value。
- `StatusPopoverView` 通过 `Localization` 获取所有按钮、标题、状态和帮助文案。
- `StatusMenuBuilder` 接收 `Localization`，构建菜单时使用当前译文，并设置 `NSMenu.userInterfaceLayoutDirection` 以支持阿拉伯语。
- SwiftUI 根视图设置 `environment(\.layoutDirection, localization.resolvedLanguage.layoutDirection)`；阿拉伯语界面使用 RTL，其他语言使用 LTR。

### 5.7 展示层改造

- 把 `StatusPresentation` 从静态中文常量改为接收 `Localization` 的展示层类型，或把 `Localization` 作为每个展示方法的显式参数。
- 状态展示仍遵守现有优先级：无电池、已充满、正在充电、低电量模式、连接电源、电池供电。
- 无障碍值的拼接使用完整格式键，例如 `accessibility.status` 接收电池、Wi-Fi、音量三段字符串。
- 比较“是否处于普通电池供电状态”时使用 `BatteryStatus` 状态字段，不再比较本地化字符串。
- `SettingsView`、`WiFiStatusView`、`BatteryStatusView`、`VolumeControlsView`、`OutputDeviceList`、`OutputDeviceRow` 中所有硬编码可见文案改为 `LocalizationKey`。
- 未找到名称的系统设备不在数据层写死中文：`VolumeReading.deviceName` 与 `AudioOutputDevice.name` 改为可选，由展示层显示本地化的“未知输出设备/无默认输出设备”。

### 5.8 字体、布局与格式化

- 不假设英文字符串宽度与中国语文案相同；说明文本允许纵向增长，标题和按钮保持合理的截断策略。
- 百分比、时间等数字使用当前 `AppLanguage.locale`。
- 应用名称 `Status Trio`、版本号、Wi-Fi、iPhone、macOS、音频设备名和 SSID 保持原文。
- 语言名称不翻译，始终以对应语言的原生写法显示，降低用户选择成本。

## 6. 测试设计

新增或扩展以下自动化测试：

1. `LocalizationTests`
   - 手动选择每种语言后 `resolvedLanguage` 正确。
   - `.system` 分别解析 `zh-CN`、`zh-TW`、`ja-JP`、`pt-BR` 等系统偏好。
   - 未知系统语言回退英语。
   - 持久化语言在重新创建实例后保持；非法值回退跟随系统。
   - `setPreference` 会发布变化，满足立即刷新接线。
   - 翻译缺少键时回退英语。
2. 翻译完整性测试
   - 遍历 `LocalizationKey.allCases`。
   - 逐一加载 12 个 `.lproj` bundle。
   - 每个键必须存在且非空。
   - 带参数键必须包含匹配数量的占位符。
3. 展示层测试
   - 简化现有 `StatusPresentationTests` 的中文断言为固定语言测试。
   - 增加英语、阿拉伯语和至少一种带占位符语言的输出断言。
   - 确认时间、音量、Wi-Fi 格数和无障碍拼接使用格式化结果。
4. 菜单与设置测试
   - `StatusMenuBuilder` 在固定语言下生成对应菜单标题。
   - `SettingsStore` 现有测试继续通过。
   - 新增语言偏好持久化测试；语言选择自身由 `LocalizationTests` 覆盖。
5. 构建验证
   - `swift test` 全部通过。
   - 运行 `bash scripts/build-app.sh release no-open`。
   - 检查 `dist/StatusTrio.app/Contents/Resources` 包含 12 个 `.lproj` 和 `InfoPlist.strings`。
   - 检查主可执行文件的 Swift Package resource bundle 包含 `Localizable.strings`。

## 7. 验收标准

- 设置页显示“语言”，包含“跟随系统”和全部 12 种语言。
- 默认选择“跟随系统”，并按 macOS 首选语言顺序解析支持语言。
- 手动选择任意支持语言后，设置页、popover、右键菜单、窗口标题、帮助和无障碍文案立即刷新。
- 阿拉伯语界面使用 RTL；切回其他语言后恢复 LTR。
- 选择在重启后保持；删除偏好或写入非法值后恢复“跟随系统”。
- 12 个 `Localizable.strings` 对 `LocalizationKey.allCases` 的覆盖率为 100%，没有空值。
- 定位权限弹窗在 App bundle 中可找到对应系统语言的 `InfoPlist.strings`。
- 现有测试通过，新增测试通过，Release App bundle 可构建且资源完整。
- 除系统或外部提供的名称外，UI 和数据层不再保留硬编码中文回退文案。

## 8. 已知限制

- macOS 定位授权弹窗由系统选择语言；应用内手动选择语言无法实时改变该弹窗。
- 语言名称保持原语言写法，不随界面语言翻译。
- 首版只包含表中 12 种语言，不为同一语言增加多个地区变体。
