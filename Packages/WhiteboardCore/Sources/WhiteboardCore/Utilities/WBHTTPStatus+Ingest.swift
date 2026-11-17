//
//  WBHTTPStatus+Ingest.swift
//  WhiteboardCore
//
//  In its own file because the ingest SDK's `RailengineError` shares its name with the retrieval
//  SDK's, and its module name is shadowed by a type, so it can't be qualified.
//

import RailengineIngest

extension WBHTTPStatus {
    static func ingestStatusCode(of error: any Error) -> Int? {
        if case RailengineError.httpError(let statusCode)? = error as? RailengineError {
            return statusCode
        }
        return nil
    }
}
