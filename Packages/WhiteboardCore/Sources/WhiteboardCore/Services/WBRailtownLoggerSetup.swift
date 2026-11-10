//
//  WBRailtownLoggerSetup.swift
//  WhiteboardCore
//

import RailtownLogger

/// Activates both Railtown uploads with the Conductr key stored in the Keychain: error logs
/// through `RailtownLogger`, and agent-run traces through `ConductrTraceUploader`. One key,
/// one entry in Settings, so they're configured together here rather than at every call site.
///
/// The two have separate `configure` calls in the SDK because the trace exchange endpoint needs
/// a host that can't be derived from the key — hence `WBConductrConfig.apiURL` below, which is the
/// host alone: the SDK owns the `/api/observe/exchange` path it appends.
/// Either can fail without taking the other down: a rejected key leaves that upload off and logs
/// a warning.
///
/// Called at launch and again whenever the key is saved, so a key entered mid-session
/// takes effect without a relaunch.
public enum WBRailtownLoggerSetup {
    public static func configure(apiKey: String) {
        do {
            try RailtownLogger.configure(
                apiKey: apiKey,
                options: RailtownOptions(isInternalLoggingEnabled: true)
            )
        } catch {
            WBLog.warning("⚠️🔗 RailtownLogger rejected the Conductr key — error-log uploads stay off: \(error)")
        }
        do {
            try ConductrTraceUploader.shared.configure(
                apiKey: apiKey,
                apiBaseURL: WBConductrConfig.apiURL,
                isInternalLoggingEnabled: true
            )
        } catch {
            WBLog.warning("⚠️🔗 ConductrTraceUploader rejected the Conductr key — agent-run uploads stay off: \(error)")
        }
    }
}
