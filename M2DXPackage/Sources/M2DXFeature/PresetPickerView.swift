// PresetPickerView.swift
// Preset selection UI with category-based sections

import SwiftUI
import M2DXCore

/// Preset picker with category sections and checkmark selection
@MainActor
struct PresetPickerView: View {
    @Binding var selectedPreset: DX7Preset?
    let onSelect: (DX7Preset) -> Void
    @Environment(\.dismiss) private var dismiss

    private let presets = DX7FactoryPresets.all

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedCategories, id: \.0) { category, categoryPresets in
                    Section(header: Text(category.rawValue.capitalized)) {
                        ForEach(categoryPresets) { preset in
                            Button {
                                onSelect(preset)
                                selectedPreset = preset
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.name)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundStyle(.primary)
                                        Text("ALG \(preset.algorithm + 1)  FB \(preset.feedback)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedPreset?.id == preset.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.cyan)
                                            .font(.body.bold())
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Presets")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            #if os(macOS)
            .frame(minWidth: 350, minHeight: 400)
            #endif
        }
    }

    /// Group presets by category, maintaining order
    private var groupedCategories: [(PresetCategory, [DX7Preset])] {
        var dict: [PresetCategory: [DX7Preset]] = [:]
        for preset in presets {
            dict[preset.category, default: []].append(preset)
        }
        // Return in the order categories appear
        var seen = Set<PresetCategory>()
        var result: [(PresetCategory, [DX7Preset])] = []
        for preset in presets {
            if !seen.contains(preset.category) {
                seen.insert(preset.category)
                if let items = dict[preset.category] {
                    result.append((preset.category, items))
                }
            }
        }
        return result
    }
}
