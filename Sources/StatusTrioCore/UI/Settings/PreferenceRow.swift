import SwiftUI

struct PreferenceRow<Content: View>: View {
    let label: LocalizationKey
    let description: LocalizationKey?
    let placesControlInline: Bool
    @EnvironmentObject private var localization: Localization
    private let content: Content

    init(
        label: LocalizationKey,
        description: LocalizationKey? = nil,
        placesControlInline: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.description = description
        self.placesControlInline = placesControlInline
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if placesControlInline {
                HStack(alignment: .center, spacing: 16) {
                    labelText
                    Spacer(minLength: 16)
                    content
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    labelText
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let description {
                Text(localization.string(description))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var labelText: some View {
        Text(localization.string(label))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
    }
}
