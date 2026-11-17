//
//  WBWhiteboardEntity+Snippet.swift
//  WhiteboardApp
//
//  How Siri shows a whiteboard as a card (27.3). In its own file so it can be dropped without
//  touching the 27.0 entity.
//

import AppIntents
import SwiftUI

@available(iOS 27.3, macOS 27.3, *)
extension WBWhiteboardEntity: SnippetRepresentableEntity {
    static var snippet: some EntitySnippetContent<WBWhiteboardEntity> {
        CardSnippet(supportedFamilies: [.standard]) { whiteboard, _ in
            WBWhiteboardCardView(whiteboard: whiteboard)
        }
    }
}

/// The card's content: title, date and meeting, summary, and the first action items.
struct WBWhiteboardCardView: View {
    let whiteboard: WBWhiteboardEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(whiteboard.title)
                .font(.headline)
            Text(whiteboard.subtitleText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !whiteboard.summary.isEmpty {
                Text(whiteboard.summary)
                    .font(.callout)
                    .lineLimit(4)
            }
            ForEach(Array(whiteboard.actionItems.prefix(4).enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "circle")
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
