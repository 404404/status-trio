import Darwin
import Foundation

final class SingleInstanceGuard {
    static var defaultLockPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/StatusTrio", isDirectory: true)
            .appendingPathComponent(lockFileName(for: Bundle.main.bundleIdentifier))
            .path
    }

    static func lockFileName(for bundleIdentifier: String?) -> String {
        let fallbackIdentifier = "com.lingsmbp.StatusTrio"
        let identifier = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIdentifier = identifier.flatMap { $0.isEmpty ? nil : $0 }
            ?? fallbackIdentifier
        let sanitizedIdentifier = resolvedIdentifier.map { character in
            character.isLetter || character.isNumber || character == "." || character == "-"
                ? character
                : "_"
        }
        return "\(String(sanitizedIdentifier)).lock"
    }

    private let descriptor: Int32

    init?(lockPath: String = SingleInstanceGuard.defaultLockPath) {
        let lockURL = URL(fileURLWithPath: lockPath)
        do {
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }

        let descriptor = lockPath.withCString { path in
            open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }

        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
