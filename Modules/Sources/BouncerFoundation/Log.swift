import OSLog

public enum Log {
    private static let subsystem = "com.bouncer.app"

    public static let menuBar = Logger(subsystem: subsystem, category: "menubar")
    public static let settings = Logger(subsystem: subsystem, category: "settings")
    public static let app = Logger(subsystem: subsystem, category: "app")

    /// Signposts for measuring hot paths (`xctrace record --template 'Time Profiler'`).
    public static let signposter = OSSignposter(subsystem: subsystem, category: "perf")
}
