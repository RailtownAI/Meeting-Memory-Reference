//
//  WBHTTPStatus.swift
//  WhiteboardCore
//

import Railengine

/// The HTTP status behind a railengine failure, so app code can tell a rejected key from a network
/// problem without importing both SDKs (each defines its own `RailengineError`).
public enum WBHTTPStatus {
    /// The status code when `error` is a railengine retrieval or ingest HTTP error, else `nil`.
    public static func code(of error: any Error) -> Int? {
        if case RailengineError.httpError(let statusCode, _)? = error as? RailengineError {
            return statusCode
        }
        return ingestStatusCode(of: error)
    }
}
