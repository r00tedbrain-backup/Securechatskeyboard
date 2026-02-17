import Foundation
import os.log

/// Unified logging for both the main app and the keyboard extension.
enum Logger {
    private static let subsystem = "com.bwt.securechats"
    private static let osLog = OSLog(subsystem: subsystem, category: "SecureChat")

    static func log(_ message: String, type: OSLogType = .default) {
        os_log("%{public}@", log: osLog, type: type, message)
    }

    static func error(_ message: String) {
        os_log("%{public}@", log: osLog, type: .error, message)
    }

    static func debug(_ message: String) {
        #if DEBUG
        os_log("%{public}@", log: osLog, type: .debug, message)
        #endif
    }
}
