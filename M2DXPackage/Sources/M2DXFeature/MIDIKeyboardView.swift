import SwiftUI

// MARK: - MIDI Keyboard View

/// Interactive piano keyboard for playing notes
public struct MIDIKeyboardView: View {
    /// Callback when a note is pressed
    let onNoteOn: (UInt8, UInt8) -> Void

    /// Callback when a note is released
    let onNoteOff: (UInt8) -> Void

    /// Base octave (0-8)
    @Binding var octave: Int

    /// Number of octaves to display
    let octaveCount: Int

    /// Currently pressed notes
    @State private var pressedNotes: Set<UInt8> = []

    public init(
        octave: Binding<Int>,
        octaveCount: Int = 2,
        onNoteOn: @escaping (UInt8, UInt8) -> Void,
        onNoteOff: @escaping (UInt8) -> Void
    ) {
        self._octave = octave
        self.octaveCount = octaveCount
        self.onNoteOn = onNoteOn
        self.onNoteOff = onNoteOff
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Octave controls
            HStack {
                Button {
                    if octave > 0 { octave -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                }
                .disabled(octave <= 0)

                Text("C\(octave)")
                    .font(.headline.monospacedDigit())
                    .frame(width: 50)

                Button {
                    if octave < 7 { octave += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                }
                .disabled(octave >= 7)

                Spacer()

                // All notes off button
                Button {
                    // Only send note off for actually pressed notes
                    for note in pressedNotes {
                        onNoteOff(note)
                    }
                    pressedNotes.removeAll()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.title2)
                }
            }
            .padding(.horizontal)

            // Keyboard
            GeometryReader { geometry in
                let whiteKeyWidth = geometry.size.width / CGFloat(7 * octaveCount)
                let blackKeyWidth = whiteKeyWidth * 0.6
                let whiteKeyHeight = geometry.size.height
                let blackKeyHeight = whiteKeyHeight * 0.6

                ZStack(alignment: .topLeading) {
                    // White keys
                    HStack(spacing: 1) {
                        ForEach(0..<(7 * octaveCount), id: \.self) { index in
                            let note = whiteKeyNote(at: index)
                            WhiteKeyView(
                                isPressed: pressedNotes.contains(note),
                                width: whiteKeyWidth - 1,
                                height: whiteKeyHeight
                            )
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        if !pressedNotes.contains(note) {
                                            pressedNotes.insert(note)
                                            onNoteOn(note, 100)
                                        }
                                    }
                                    .onEnded { _ in
                                        pressedNotes.remove(note)
                                        onNoteOff(note)
                                    }
                            )
                        }
                    }

                    // Black keys
                    ForEach(0..<(7 * octaveCount), id: \.self) { index in
                        if let note = blackKeyNote(at: index) {
                            BlackKeyView(
                                isPressed: pressedNotes.contains(note),
                                width: blackKeyWidth,
                                height: blackKeyHeight
                            )
                            .offset(x: blackKeyOffset(at: index, whiteKeyWidth: whiteKeyWidth, blackKeyWidth: blackKeyWidth))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        if !pressedNotes.contains(note) {
                                            pressedNotes.insert(note)
                                            onNoteOn(note, 100)
                                        }
                                    }
                                    .onEnded { _ in
                                        pressedNotes.remove(note)
                                        onNoteOff(note)
                                    }
                            )
                        }
                    }
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Note Calculations

    /// Get MIDI note number for white key at index
    private func whiteKeyNote(at index: Int) -> UInt8 {
        let octaveOffset = index / 7
        let keyInOctave = index % 7
        let noteOffsets = [0, 2, 4, 5, 7, 9, 11]  // C, D, E, F, G, A, B
        let midiNote = (octave + octaveOffset) * 12 + noteOffsets[keyInOctave]
        return UInt8(min(127, max(0, midiNote)))
    }

    /// Get MIDI note number for black key at index (nil if no black key)
    private func blackKeyNote(at index: Int) -> UInt8? {
        let keyInOctave = index % 7
        // Black keys: C#, D#, F#, G#, A# (after C, D, F, G, A)
        guard keyInOctave != 2 && keyInOctave != 6 else { return nil }  // No black key after E and B

        let octaveOffset = index / 7
        let noteOffsets = [1, 3, -1, 6, 8, 10, -1]  // C#, D#, -, F#, G#, A#, -
        guard noteOffsets[keyInOctave] >= 0 else { return nil }

        let midiNote = (octave + octaveOffset) * 12 + noteOffsets[keyInOctave]
        return UInt8(min(127, max(0, midiNote)))
    }

    /// Calculate x offset for black key
    private func blackKeyOffset(at index: Int, whiteKeyWidth: CGFloat, blackKeyWidth: CGFloat) -> CGFloat {
        let whiteKeyIndex = CGFloat(index)
        return whiteKeyIndex * whiteKeyWidth + whiteKeyWidth - blackKeyWidth / 2
    }
}

// MARK: - White Key View

struct WhiteKeyView: View {
    let isPressed: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isPressed ? Color.blue.opacity(0.3) : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            .frame(width: width, height: height)
    }
}

// MARK: - Black Key View

struct BlackKeyView: View {
    let isPressed: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: isPressed ? [.blue, .blue.opacity(0.7)] : [.black, .gray.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
            .frame(width: width, height: height)
    }
}

// MARK: - Compact Keyboard

/// A more compact keyboard for space-constrained layouts
public struct CompactKeyboardView: View {
    let onNoteOn: (UInt8, UInt8) -> Void
    let onNoteOff: (UInt8) -> Void
    @Binding var octave: Int

    @State private var pressedNotes: Set<UInt8> = []

    public init(
        octave: Binding<Int>,
        onNoteOn: @escaping (UInt8, UInt8) -> Void,
        onNoteOff: @escaping (UInt8) -> Void
    ) {
        self._octave = octave
        self.onNoteOn = onNoteOn
        self.onNoteOff = onNoteOff
    }

    // Note names for one octave
    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    public var body: some View {
        VStack(spacing: 8) {
            // Octave selector
            HStack {
                Button {
                    if octave > 0 { octave -= 1 }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .disabled(octave <= 0)

                Text("Octave \(octave)")
                    .font(.caption.monospacedDigit())

                Button {
                    if octave < 7 { octave += 1 }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(octave >= 7)
            }

            // Note buttons grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(0..<12, id: \.self) { noteIndex in
                    let note = UInt8(octave * 12 + noteIndex)
                    let isBlackKey = [1, 3, 6, 8, 10].contains(noteIndex)

                    Button {
                        // Toggle note
                        if pressedNotes.contains(note) {
                            pressedNotes.remove(note)
                            onNoteOff(note)
                        } else {
                            pressedNotes.insert(note)
                            onNoteOn(note, 100)
                        }
                    } label: {
                        Text(noteNames[noteIndex])
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(pressedNotes.contains(note) ? .blue : (isBlackKey ? .gray : .white))
                            )
                            .foregroundStyle(pressedNotes.contains(note) ? .white : (isBlackKey ? .white : .black))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
        )
    }
}

// MARK: - Preview

#Preview("MIDI Keyboard") {
    VStack {
        MIDIKeyboardView(
            octave: .constant(4),
            octaveCount: 2,
            onNoteOn: { note, vel in print("Note On: \(note) vel: \(vel)") },
            onNoteOff: { note in print("Note Off: \(note)") }
        )
        .padding()

        CompactKeyboardView(
            octave: .constant(4),
            onNoteOn: { note, vel in print("Note On: \(note)") },
            onNoteOff: { note in print("Note Off: \(note)") }
        )
        .padding()
    }
}
