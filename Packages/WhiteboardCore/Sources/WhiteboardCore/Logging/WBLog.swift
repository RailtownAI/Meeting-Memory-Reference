import Dispatch
import Logging

/// Application logging facade backed by swift-log.
///
/// Call `WBLog.setup()` once at app launch (before any views initialize) to bootstrap the logging
/// backend. Bootstrapping is process-global, so each app (iOS, macOS) calls `setup()` from its
/// `App` init; the facade itself lives in Core so any layer — including Core — can log through it.
///
/// Messages are `@autoclosure`, so the string is only built if the log level is active, and the
/// build + write happen on a background queue so logging never blocks the caller. `@Sendable`
/// snapshots value-type interpolations at call time, so deferral can't log a later-mutated value.
public enum WBLog {
    /// Minimum level to emit. Mirrors swift-log's levels so the backend stays hidden behind the facade.
    public enum Level: Sendable {
        case trace, debug, info, warning, error

        fileprivate var swiftLog: Logger.Level {
            switch self {
            case .trace:
                return .trace
            case .debug:
                return .debug
            case .info:
                return .info
            case .warning:
                return .warning
            case .error:
                return .error
            }
        }
    }

    /// Default minimum level: verbose in debug builds, quieter in release.
    #if DEBUG
    public static let defaultLevel: Level = .debug
    #else
    public static let defaultLevel: Level = .info
    #endif

    private static let logger = Logger(label: "ai.railtown.whiteboard")
    private static let queue = DispatchQueue(label: "ai.railtown.whiteboard.log", qos: .utility)

    // Set once at launch before any concurrency, so the unsafe access is fine.
    nonisolated(unsafe) private static var hasBootstrapped = false

    /// Bootstraps logging at `level`. Call once at app launch, before any views initialize; extra
    /// calls are ignored (the backend can only be bootstrapped once per process).
    public static func setup(level: Level = defaultLevel) {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = level.swiftLog
            return handler
        }
    }

    public static func trace(_ message: @autoclosure @escaping @Sendable () -> String) {
        queue.async { logger.trace("\(message())") }
    }

    public static func debug(_ message: @autoclosure @escaping @Sendable () -> String) {
        queue.async { logger.debug("\(message())") }
    }

    public static func info(_ message: @autoclosure @escaping @Sendable () -> String) {
        queue.async { logger.info("\(message())") }
    }

    public static func warning(_ message: @autoclosure @escaping @Sendable () -> String) {
        queue.async { logger.warning("\(message())") }
    }

    public static func error(_ message: @autoclosure @escaping @Sendable () -> String) {
        queue.async { logger.error("\(message())") }
    }
}
