import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject private var localization: Localization

    var body: some View {
        PreferencesPane {
            HStack(alignment: .top, spacing: 12) {
                Text("Status\nTrio")
                    .font(.system(size: 44, weight: .ultraLight))
                    .lineSpacing(-4)
                    .frame(width: 132, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        localization.format(
                            .settingsAboutVersion,
                            AppMetadata.versionDisplayString
                        )
                    )
                    .font(.system(size: 11, weight: .light))

                    Text(localization.string(.settingsAboutDescription))
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(localization.string(.settingsAboutCopyright))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 8) {
                Link(destination: AppMetadata.repositoryURL) {
                    Label(
                        localization.string(.settingsAboutRepository),
                        systemImage: "arrow.up.right.square"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Link(destination: AppMetadata.authorURL) {
                    Label(AppMetadata.authorName, systemImage: "person.crop.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Link(destination: AppMetadata.authorWebsiteURL) {
                    Label(
                        localization.string(.settingsAboutWebsite),
                        systemImage: "globe"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(
                "\(localization.string(.settingsAboutAuthor)) · " +
                    "\(AppMetadata.authorName) · " +
                    "\(localization.string(.settingsAboutAuthorRole))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
