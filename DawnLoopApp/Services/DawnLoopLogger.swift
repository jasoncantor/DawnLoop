import OSLog

enum DawnLoopLogger {
    static let subsystem = "com.dawnloop.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let homeKit = Logger(subsystem: subsystem, category: "homekit")
    static let automation = Logger(subsystem: subsystem, category: "automation")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
}
