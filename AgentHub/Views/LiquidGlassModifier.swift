//
//  LiquidGlassModifier.swift
//  AgentHub
//
//  Created by Timothy Zelinsky on 5/3/2026.
//
import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .background {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 0) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
}
