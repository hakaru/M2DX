// M2DXMacApp.swift
// M2DX - MIDI 2.0 × FM Synthesis Reference Instrument (macOS)

import SwiftUI
import M2DXFeature

@main
struct M2DXMacApp: App {
    var body: some Scene {
        WindowGroup {
            M2DXRootView()
        }
        .defaultSize(width: 480, height: 700)
    }
}
