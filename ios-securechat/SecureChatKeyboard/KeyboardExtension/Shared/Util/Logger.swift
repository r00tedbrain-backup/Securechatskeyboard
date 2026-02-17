import Foundation
import os.log

/// Unified logging for both the main app and the keyboard extension.
///
/// In DEBUG builds, all messages are logged with %{public} for easy debugging.
/// In RELEASE builds, verbose log/debug are disabled entirely to prevent
/// leaking sensitive data (decrypted messages, UUIDs, key metadata) to the
/// system log. Only errors are logged, and they use %{private} redaction.
enum Logger {
    private static let subsystem = "com.bwt.securechats"
    private static let osLog = OSLog(subsystem: subsystem, category: "SecureChat")

    static func log(_ message: String, type: OSLogType = .default) {
        #if DEBUG
        os_log("%{public}@", log: osLog, type: type, message)
        #endif
    }

    static func error(_ message: String) {
        #if DEBUG
        os_log("%{public}@", log: osLog, type: .error, message)
        #else
        os_log("%{private}@", log: osLog, type: .error, message)
        #endif
    }

    static func debug(_ message: String) {
        #if DEBUG
        os_log("%{public}@", log: osLog, type: .debug, message)
        #endif
    }
}
