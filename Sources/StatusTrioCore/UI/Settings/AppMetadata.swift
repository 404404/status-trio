import Foundation

enum AppMetadata {
    static let name = "Status Trio"
    static let repositoryDisplayName = "github.com/lingyired/status-trio"
    static let repositoryURL = URL(string: "https://github.com/lingyired/status-trio")!
    static let authorName = "lingyired"
    static let authorURL = URL(string: "https://github.com/lingyired")!

    static var versionDisplayString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
