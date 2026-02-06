// PlatformColors.swift
// Cross-platform Color extensions for iOS/macOS

import SwiftUI

extension Color {
    /// System background color (iOS: .systemBackground, macOS: .windowBackgroundColor)
    static var m2dxBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// Secondary system background color (iOS: .secondarySystemBackground, macOS: .controlBackgroundColor)
    static var m2dxSecondaryBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
