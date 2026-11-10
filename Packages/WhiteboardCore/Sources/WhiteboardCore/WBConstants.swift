//
//  WBConstants.swift
//  WhiteboardCore
//
//  Created by Mark Su on 2026-07-31.
//

public enum WBConductrConfig {
    /// Host of the Railtown Conductr API — the host only. `ConductrTraceUploader` owns the
    /// `/api/observe/exchange` path and appends it to this, so a `/api` here would be uploaded to
    /// `/api/api/observe/exchange`. Points at production alongside the railengine environment below.
    public static let apiURL = "https://cndr.railtown.ai"
}

public enum WBRailengineConfig {
    /// Railengine environment every client must target — a PAT and engine id only work within
    /// the environment that issued them. Points at production.
    public static let apiURL = "https://cndr.railtown.ai"
    /// Fill in the engine ids from your Railengine environment before building.
    public static let whiteboardEngineID = ""
    public static let calendarEngineID = ""
}
