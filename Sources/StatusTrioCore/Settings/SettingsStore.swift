import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let iconSizeRange: ClosedRange<Double> = 20...32
    static let defaultIconSize: Double = 28
    static let iconSizeDefaultsKey = "menuBarIconSize"

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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = (defaults.object(forKey: Self.iconSizeDefaultsKey) as? NSNumber)?.doubleValue
        self.iconSize = Self.clampedIconSize(stored ?? Self.defaultIconSize)
    }

    static func clampedIconSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultIconSize }
        return min(iconSizeRange.upperBound, max(iconSizeRange.lowerBound, value))
    }
}
