//
//  PhotoSearchTool.swift
//  WhiteboardCore
//
//  Created by Mark Su on 2026-07-30.
//

import Foundation
import RailtracksSwift

struct PhotoSearchTool: RTSToolNode {
    typealias Output = String
    
    let id: UUID = UUID()
    let toolName: String = "Photo_Summary_Search"
    var toolDescription: String {
        "Search for photos via photo summary in vector store. Returns a list of structured metadata of the photo."
    }
    var parameterSchema: RTSToolSchema {
        RTSToolSchema(
            parameters: [
                .init(name: "query", description: "The search query to look up in vector store", type: .string)
            ]
        )
    }
    var inputs: RTSInput = [:]
    
    let callableRoutine = RTSClosure { inputs in
        guard case let .string(query) = inputs["query"] else {
            throw RTSError.missingInput("query")
        }

        // TODO: possible improvement — have the store surface `SearchDocument.score` (vector
        // relevance) alongside each record, so the agent gets a concrete signal for judging its
        // relevance cutoff instead of eyeballing summaries.
        let results = try await WBWhiteboardRecordStore().search(query: query)

        let slimResults = results.map { LLMSearchResult(from: $0) }
        let jsonData = try JSONEncoder().encode(slimResults)
        let jsonString = String(decoding: jsonData, as: UTF8.self)
        return ["results": .string(jsonString)]
    }
    
    /// Subset of `WBWhiteboardRecord` for the LLM: keeps the record `id` for reference and all
    /// content fields, but drops the other identifier fields (`meetingId`, `eventUID`, `imageId`).
    private struct LLMSearchResult: Codable {
        let id: String
        let kind: String
        let occurrenceStart: String
        let capturedAt: String
        let capturedAtEpoch: Int
        let title: String
        let summary: String
        let markdown: String
        let ocrText: String
        let keywords: [String]
        let actionItems: [WBActionItem]
        let capturedByDevice: String

        init(from record: WBWhiteboardRecord) {
            id = record.id
            kind = record.kind
            occurrenceStart = record.occurrenceStart
            capturedAt = record.capturedAt
            capturedAtEpoch = record.capturedAtEpoch
            title = record.title
            summary = record.summary
            markdown = record.markdown
            ocrText = record.ocrText
            keywords = record.keywords
            actionItems = record.actionItems
            capturedByDevice = record.capturedByDevice
        }
    }
}
