import Darwin
import Foundation

final class SingleInstanceGuard {
    static var defaultLockPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/StatusTrio", isDirectory: true)
            .appendingPathComponent("StatusTrio.lock")
            .path
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
