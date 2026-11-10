//
//  OnHoverViewModifier.swift
//  WhiteboardApp
//
//  Created by Fabricio Sperotto Sffair on 30/07/26.
//

import SwiftUI

struct OnHoverViewModifier: ViewModifier {
    
    @Binding private var isHovering: Bool
    var isEnabled: Bool

    init(isHovering: Binding<Bool>, isEnabled: Bool = false) {
        _isHovering = isHovering
        self.isEnabled = isEnabled
    }

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                Task { @MainActor in
                    if (isHovering && isEnabled) {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
    }
}

public extension View {
    func onHover(isHovering: Binding<Bool>, isEnabled: Bool = true) -> some View {
        modifier(OnHoverViewModifier(isHovering: isHovering, isEnabled: isEnabled))
    }
}
