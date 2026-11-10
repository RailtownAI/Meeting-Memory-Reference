//
//  HoverOpacityModifier.swift
//  WhiteboardApp
//
//  Created by Fabricio Sperotto Sffair on 30/07/26.
//

import SwiftUI

struct HoverOpacityModifier: ViewModifier {
    
    let isEnabled: Bool
    @State private var isHovering: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(isHovering && isEnabled ? 0.8 : 1.0)
            .onHover(isHovering: $isHovering, isEnabled: isEnabled)
    }
}

public extension View {
    func hoverOpacity(isEnabled: Bool = true) -> some View {
        modifier(HoverOpacityModifier(isEnabled: isEnabled))
    }
}
