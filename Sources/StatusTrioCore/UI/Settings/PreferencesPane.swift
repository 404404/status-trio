import SwiftUI

struct PreferencesPane<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(20)
        .frame(width: SettingsTabViewController.contentWidth, alignment: .topLeading)
        .background(Color.clear)
    }
}
