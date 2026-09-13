import Combine
import Foundation

enum LanguagePreference: Hashable, Identifiable, Sendable {
    case system
    case language(AppLanguage)

    var id: String {
        switch self {
        case .system:
            "system"
        case .language(let language):
            language.rawValue
        }
    }

    func resolvedLanguage(preferredLanguages: [String]) -> AppLanguage {
        switch self {
        case .system:
            AppLanguage.resolved(preferredLanguages: preferredLanguages)
        case .language(let language):
            language
        }
    }
}

@MainActor
final class Localization: ObservableObject {
    static let defaultsKey = "appLanguage"

    @Published private(set) var preference: LanguagePreference
    @Published private(set) var resolvedLanguage: AppLanguage

    private let defaults: UserDefaults
    private var preferredLanguages: [String]
    private var localeObserver: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages

        let storedPreference = defaults.string(forKey: Self.defaultsKey)
        let preference: LanguagePreference
        if let storedPreference, let language = AppLanguage(rawValue: storedPreference) {
            preference = .language(language)
        } else {
            preference = .system
        }

        self.preference = preference
        self.resolvedLanguage = preference.resolvedLanguage(
            preferredLanguages: preferredLanguages
        )

        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSystemLanguage()
            }
        }
    }

    isolated deinit {
        if let localeObserver {
            NotificationCenter.default.removeObserver(localeObserver)
        }
    }

    func setPreference(_ newPreference: LanguagePreference) {
        preference = newPreference
        switch newPreference {
        case .system:
            defaults.removeObject(forKey: Self.defaultsKey)
        case .language(let language):
            defaults.set(language.rawValue, forKey: Self.defaultsKey)
        }
        resolvedLanguage = newPreference.resolvedLanguage(
            preferredLanguages: preferredLanguages
        )
    }

    func string(_ key: LocalizationKey) -> String {
        if let value = localizedString(key, in: resolvedLanguage) {
            return value
        }
        if resolvedLanguage != .english,
           let value = localizedString(key, in: .english) {
            return value
        }
        return key.rawValue
    }

    func format(_ key: LocalizationKey, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: resolvedLanguage.locale,
            arguments: arguments
        )
    }

    private func refreshSystemLanguage() {
        preferredLanguages = Locale.preferredLanguages
        guard preference == .system else { return }
        resolvedLanguage = AppLanguage.resolved(preferredLanguages: preferredLanguages)
    }

    private func localizedString(
        _ key: LocalizationKey,
        in language: AppLanguage
    ) -> String? {
        guard let bundle = bundle(for: language) else { return nil }
        let value = bundle.localizedString(
            forKey: key.rawValue,
            value: nil,
            table: nil
        )
        guard !value.isEmpty, value != key.rawValue else { return nil }
        return value
    }

    private func bundle(for language: AppLanguage) -> Bundle? {
        Bundle.module
            .url(forResource: language.rawValue, withExtension: "lproj")
            .flatMap(Bundle.init(url:))
    }
}
