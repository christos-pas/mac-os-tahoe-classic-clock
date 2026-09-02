import Foundation
import os.log

enum LockClockLog {
    private static let logger = Logger(subsystem: "app.lockclock.LockClock", category: "LockClock")

    static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return Settings.shared.debugLoggingEnabled || Settings.isDebugMode
        #endif
    }

    static func info(_ message: String) {
        guard isEnabled else { return }
        logger.info("\(message, privacy: .public)")
        NSLog("[LockClock] %@", message)
        FileHandle.standardError.write(Data("[LockClock] \(message)\n".utf8))
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        NSLog("[LockClock] %@", message)
        FileHandle.standardError.write(Data("[LockClock] \(message)\n".utf8))
    }
}
