import SwiftUI

struct BasicsSettingsPane: View {
    @ObservedObject var localization: Localization

    var body: some View {
        PreferencesPane {
            PreferenceRow(
                label: .settingsLanguage,
                description: .settingsLanguageDescription,
                placesControlInline: true
            ) {
                Picker(
                    localization.string(.settingsLanguage),
                    selection: $localization.preference
                ) {
                    Text(localization.string(.settingsLanguageFollowSystem))
                        .tag(LanguagePreference.system)

                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName)
                            .tag(LanguagePreference.language(language))
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }
        }
    }
}
