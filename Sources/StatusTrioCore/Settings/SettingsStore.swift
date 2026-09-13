import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let iconSizeRange: ClosedRange<Double> = 20...32
    static let defaultIconSize: Double = 28
    static let iconSizeDefaultsKey = "menuBarIconSize"

    static let batteryCriticalThresholdRange: ClosedRange<Double> = 0...100
    static let defaultBatteryCriticalThreshold: Double = 20
    static let batterySymbolScaleRange: ClosedRange<Double> = 0.9...1.1
    static let defaultBatterySymbolScale: Double = 1
    static let showsBatteryPercentageDefaultsKey = "showsBatteryPercentage"
    static let showsChargingIndicatorDefaultsKey = "showsChargingIndicator"
    static let usesBatteryStatusColorsDefaultsKey = "usesBatteryStatusColors"
    static let batteryCriticalThresholdDefaultsKey = "batteryCriticalThreshold"
    static let batterySymbolScaleDefaultsKey = "batterySymbolScale"

    @Published var iconSize: Double {
        didSet {
            let clamped = Self.clampedIconSize(iconSize)
            // 写入越界值时先夹取再落盘，夹取会再次触发 didSet，一次后收敛。
            guard clamped == iconSize else {
                iconSize = clamped
                return
            }
            defaults.set(clamped, forKey: Self.iconSizeDefaultsKey)
        }
    }

    @Published var showsBatteryPercentage: Bool {
        didSet {
            defaults.set(showsBatteryPercentage, forKey: Self.showsBatteryPercentageDefaultsKey)
        }
    }

    @Published var showsChargingIndicator: Bool {
        didSet {
            defaults.set(showsChargingIndicator, forKey: Self.showsChargingIndicatorDefaultsKey)
        }
    }

    @Published var usesBatteryStatusColors: Bool {
        didSet {
            defaults.set(usesBatteryStatusColors, forKey: Self.usesBatteryStatusColorsDefaultsKey)
        }
    }

    @Published var batterySymbolScale: Double {
        didSet {
            let clamped = Self.clampedBatterySymbolScale(batterySymbolScale)
            guard clamped == batterySymbolScale else {
                batterySymbolScale = clamped
                return
            }
            defaults.set(clamped, forKey: Self.batterySymbolScaleDefaultsKey)
        }
    }

    @Published var batteryCriticalThreshold: Double {
        didSet {
            let clamped = Self.clampedBatteryCriticalThreshold(batteryCriticalThreshold)
            guard clamped == batteryCriticalThreshold else {
                batteryCriticalThreshold = clamped
                return
            }
            defaults.set(clamped, forKey: Self.batteryCriticalThresholdDefaultsKey)
        }
    }

    var isBatterySymbolSizeEnabled: Bool {
        showsBatteryPercentage || showsChargingIndicator
    }

    var batteryIconOptions: BatteryIconOptions {
        BatteryIconOptions(
            showsPercentage: showsBatteryPercentage,
            showsChargingIndicator: showsChargingIndicator,
            usesStatusColors: usesBatteryStatusColors,
            criticalThreshold: Int(batteryCriticalThreshold.rounded()),
            textScale: batterySymbolScale * BatteryIconOptions.defaultTextScale
        )
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedIconSize = (defaults.object(forKey: Self.iconSizeDefaultsKey) as? NSNumber)?.doubleValue
        let storedCriticalThreshold = (defaults.object(forKey: Self.batteryCriticalThresholdDefaultsKey) as? NSNumber)?.doubleValue
        let storedBatterySymbolScale = (defaults.object(forKey: Self.batterySymbolScaleDefaultsKey) as? NSNumber)?.doubleValue

        self.iconSize = Self.clampedIconSize(storedIconSize ?? Self.defaultIconSize)
        self.showsBatteryPercentage = defaults.object(forKey: Self.showsBatteryPercentageDefaultsKey) as? Bool ?? true
        self.showsChargingIndicator = defaults.object(forKey: Self.showsChargingIndicatorDefaultsKey) as? Bool ?? true
        self.usesBatteryStatusColors = defaults.object(forKey: Self.usesBatteryStatusColorsDefaultsKey) as? Bool ?? true
        self.batterySymbolScale = Self.clampedBatterySymbolScale(
            storedBatterySymbolScale ?? Self.defaultBatterySymbolScale
        )
        self.batteryCriticalThreshold = Self.clampedBatteryCriticalThreshold(
            storedCriticalThreshold ?? Self.defaultBatteryCriticalThreshold
        )
    }

    static func clampedIconSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultIconSize }
        return min(iconSizeRange.upperBound, max(iconSizeRange.lowerBound, value))
    }

    static func clampedBatterySymbolScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBatterySymbolScale }
        return min(
            batterySymbolScaleRange.upperBound,
            max(batterySymbolScaleRange.lowerBound, value)
        )
    }

    static func clampedBatteryCriticalThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBatteryCriticalThreshold }
        return min(
            batteryCriticalThresholdRange.upperBound,
            max(batteryCriticalThresholdRange.lowerBound, value)
        ).rounded()
    }
}
