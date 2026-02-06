// DX7FactoryPresets.swift
// Factory preset definitions based on DX7 ROM1A cartridge

import Foundation

/// DX7 factory presets (ROM1A-based + INIT VOICE)
public enum DX7FactoryPresets {

    /// All factory presets
    public static let all: [DX7Preset] = [
        initVoice,
        ePiano1,
        bass1,
        brass1,
        strings1,
        eOrgan1,
        marimba,
        harpsichord1,
        flute1,
        clav1,
    ]

    // MARK: - 1. INIT VOICE

    /// Basic init voice: OP1 only sine wave
    public static let initVoice = DX7Preset(
        name: "INIT VOICE",
        algorithm: 0,
        feedback: 0,
        operators: [
            // OP1 (carrier, sine wave at full level)
            DX7OperatorPreset(
                outputLevel: 99, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 99, egRate3: 99, egRate4: 99,
                egLevel1: 99, egLevel2: 99, egLevel3: 99, egLevel4: 0
            ),
            // OP2-6 (silent)
            DX7OperatorPreset(outputLevel: 0, frequencyCoarse: 1, frequencyFine: 0, detune: 7),
            DX7OperatorPreset(outputLevel: 0, frequencyCoarse: 1, frequencyFine: 0, detune: 7),
            DX7OperatorPreset(outputLevel: 0, frequencyCoarse: 1, frequencyFine: 0, detune: 7),
            DX7OperatorPreset(outputLevel: 0, frequencyCoarse: 1, frequencyFine: 0, detune: 7),
            DX7OperatorPreset(outputLevel: 0, frequencyCoarse: 1, frequencyFine: 0, detune: 7),
        ],
        category: .other
    )

    // MARK: - 2. E.PIANO 1

    /// DX7's most iconic sound — Rhodes-style electric piano
    /// Algorithm 5: [6]->5 | 4->3 | 2->1 (3 carriers)
    public static let ePiano1 = DX7Preset(
        name: "E.PIANO 1",
        algorithm: 4,
        feedback: 6,
        operators: [
            // OP1 (carrier): fundamental tone
            DX7OperatorPreset(
                outputLevel: 99, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 96, egRate2: 25, egRate3: 25, egRate4: 67,
                egLevel1: 99, egLevel2: 75, egLevel3: 60, egLevel4: 0
            ),
            // OP2 (modulator→OP1): harmonic richness
            DX7OperatorPreset(
                outputLevel: 82, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 96, egRate2: 32, egRate3: 20, egRate4: 65,
                egLevel1: 99, egLevel2: 50, egLevel3: 25, egLevel4: 0
            ),
            // OP3 (carrier): bell overtone
            DX7OperatorPreset(
                outputLevel: 86, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 95, egRate2: 50, egRate3: 35, egRate4: 78,
                egLevel1: 99, egLevel2: 75, egLevel3: 60, egLevel4: 0
            ),
            // OP4 (modulator→OP3): bell attack
            DX7OperatorPreset(
                outputLevel: 76, frequencyCoarse: 14, frequencyFine: 0, detune: 7,
                egRate1: 95, egRate2: 50, egRate3: 35, egRate4: 78,
                egLevel1: 99, egLevel2: 25, egLevel3: 10, egLevel4: 0
            ),
            // OP5 (carrier): body resonance
            DX7OperatorPreset(
                outputLevel: 86, frequencyCoarse: 1, frequencyFine: 0, detune: 8,
                egRate1: 95, egRate2: 32, egRate3: 25, egRate4: 70,
                egLevel1: 99, egLevel2: 80, egLevel3: 65, egLevel4: 0
            ),
            // OP6 (modulator→OP5, feedback): harmonic shimmer
            DX7OperatorPreset(
                outputLevel: 72, frequencyCoarse: 1, frequencyFine: 0, detune: 6,
                feedback: 6,
                egRate1: 95, egRate2: 45, egRate3: 30, egRate4: 70,
                egLevel1: 99, egLevel2: 60, egLevel3: 35, egLevel4: 0
            ),
        ],
        category: .keys
    )

    // MARK: - 3. BASS 1

    /// Punchy FM bass
    /// Algorithm 5: [6]->5 | 4->3 | 2->1 (3 carriers)
    public static let bass1 = DX7Preset(
        name: "BASS 1",
        algorithm: 4,
        feedback: 6,
        operators: [
            // OP1 (carrier): fundamental bass
            DX7OperatorPreset(
                outputLevel: 99, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 55, egRate3: 40, egRate4: 65,
                egLevel1: 99, egLevel2: 90, egLevel3: 85, egLevel4: 0
            ),
            // OP2 (modulator→OP1): sub harmonics
            DX7OperatorPreset(
                outputLevel: 87, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 70, egRate3: 45, egRate4: 60,
                egLevel1: 99, egLevel2: 55, egLevel3: 30, egLevel4: 0
            ),
            // OP3 (carrier): attack click
            DX7OperatorPreset(
                outputLevel: 80, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 65, egRate3: 40, egRate4: 60,
                egLevel1: 99, egLevel2: 85, egLevel3: 75, egLevel4: 0
            ),
            // OP4 (modulator→OP3): attack brightness
            DX7OperatorPreset(
                outputLevel: 82, frequencyCoarse: 3, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 80, egRate3: 50, egRate4: 60,
                egLevel1: 99, egLevel2: 25, egLevel3: 10, egLevel4: 0
            ),
            // OP5 (carrier): low body
            DX7OperatorPreset(
                outputLevel: 75, frequencyCoarse: 0, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 50, egRate3: 35, egRate4: 65,
                egLevel1: 99, egLevel2: 90, egLevel3: 80, egLevel4: 0
            ),
            // OP6 (modulator→OP5, feedback): grit
            DX7OperatorPreset(
                outputLevel: 65, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                feedback: 5,
                egRate1: 99, egRate2: 75, egRate3: 50, egRate4: 60,
                egLevel1: 99, egLevel2: 40, egLevel3: 20, egLevel4: 0
            ),
        ],
        category: .bass
    )

    // MARK: - 4. BRASS 1

    /// Bright brass ensemble
    /// Algorithm 22: [6]->{5,4,3} | 2->1 (4 carriers)
    public static let brass1 = DX7Preset(
        name: "BRASS 1",
        algorithm: 21,
        feedback: 7,
        operators: [
            // OP1 (carrier): main brass body
            DX7OperatorPreset(
                outputLevel: 99, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 72, egRate2: 50, egRate3: 35, egRate4: 60,
                egLevel1: 99, egLevel2: 92, egLevel3: 88, egLevel4: 0
            ),
            // OP2 (modulator→OP1): breath noise
            DX7OperatorPreset(
                outputLevel: 78, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 65, egRate2: 55, egRate3: 40, egRate4: 60,
                egLevel1: 99, egLevel2: 70, egLevel3: 55, egLevel4: 0
            ),
            // OP3 (carrier): upper partial
            DX7OperatorPreset(
                outputLevel: 80, frequencyCoarse: 1, frequencyFine: 0, detune: 8,
                egRate1: 70, egRate2: 48, egRate3: 35, egRate4: 60,
                egLevel1: 99, egLevel2: 88, egLevel3: 82, egLevel4: 0
            ),
            // OP4 (carrier): brightness partial
            DX7OperatorPreset(
                outputLevel: 72, frequencyCoarse: 1, frequencyFine: 0, detune: 6,
                egRate1: 75, egRate2: 52, egRate3: 38, egRate4: 62,
                egLevel1: 99, egLevel2: 85, egLevel3: 78, egLevel4: 0
            ),
            // OP5 (carrier): sub resonance
            DX7OperatorPreset(
                outputLevel: 68, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 68, egRate2: 45, egRate3: 32, egRate4: 58,
                egLevel1: 99, egLevel2: 90, egLevel3: 85, egLevel4: 0
            ),
            // OP6 (modulator, feedback): harmonic generator
            DX7OperatorPreset(
                outputLevel: 85, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                feedback: 7,
                egRate1: 60, egRate2: 50, egRate3: 40, egRate4: 60,
                egLevel1: 99, egLevel2: 65, egLevel3: 50, egLevel4: 0
            ),
        ],
        category: .brass
    )

    // MARK: - 5. STRINGS 1

    /// Slow-attack string ensemble
    /// Algorithm 1: [6]->5->4->3 | 2->1 (2 carriers)
    public static let strings1 = DX7Preset(
        name: "STRINGS 1",
        algorithm: 0,
        feedback: 5,
        operators: [
            // OP1 (carrier): string fundamental
            DX7OperatorPreset(
                outputLevel: 99, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 35, egRate2: 30, egRate3: 25, egRate4: 45,
                egLevel1: 99, egLevel2: 95, egLevel3: 92, egLevel4: 0
            ),
            // OP2 (modulator→OP1): vibrato/movement
            DX7OperatorPreset(
                outputLevel: 72, frequencyCoarse: 1, frequencyFine: 0, detune: 8,
                egRate1: 38, egRate2: 32, egRate3: 28, egRate4: 48,
                egLevel1: 99, egLevel2: 65, egLevel3: 55, egLevel4: 0
            ),
            // OP3 (carrier): octave up shimmer
            DX7OperatorPreset(
                outputLevel: 82, frequencyCoarse: 2, frequencyFine: 0, detune: 6,
                egRate1: 32, egRate2: 28, egRate3: 22, egRate4: 42,
                egLevel1: 99, egLevel2: 92, egLevel3: 88, egLevel4: 0
            ),
            // OP4 (modulator→OP3): overtone depth
            DX7OperatorPreset(
                outputLevel: 60, frequencyCoarse: 2, frequencyFine: 0, detune: 7,
                egRate1: 30, egRate2: 25, egRate3: 20, egRate4: 40,
                egLevel1: 99, egLevel2: 50, egLevel3: 35, egLevel4: 0
            ),
            // OP5 (modulator→OP4→OP3): brightness mod
            DX7OperatorPreset(
                outputLevel: 55, frequencyCoarse: 3, frequencyFine: 0, detune: 7,
                egRate1: 28, egRate2: 22, egRate3: 18, egRate4: 38,
                egLevel1: 99, egLevel2: 45, egLevel3: 30, egLevel4: 0
            ),
            // OP6 (modulator, feedback): noise/rosin
            DX7OperatorPreset(
                outputLevel: 48, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                feedback: 5,
                egRate1: 25, egRate2: 20, egRate3: 15, egRate4: 35,
                egLevel1: 99, egLevel2: 40, egLevel3: 25, egLevel4: 0
            ),
        ],
        category: .strings
    )

    // MARK: - 6. E.ORGAN 1

    /// Drawbar organ
    /// Algorithm 32: all 6 carriers (pure additive)
    public static let eOrgan1 = DX7Preset(
        name: "E.ORGAN 1",
        algorithm: 31,
        feedback: 4,
        operators: [
            // OP1: fundamental (8')
            DX7OperatorPreset(
                outputLevel: 95, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 80, egRate3: 80, egRate4: 85,
                egLevel1: 99, egLevel2: 99, egLevel3: 99, egLevel4: 0
            ),
            // OP2: sub octave (16')
            DX7OperatorPreset(
                outputLevel: 85, frequencyCoarse: 0, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 80, egRate3: 80, egRate4: 85,
                egLevel1: 99, egLevel2: 99, egLevel3: 99, egLevel4: 0
            ),
            // OP3: octave (4')
            DX7OperatorPreset(
                outputLevel: 82, frequencyCoarse: 2, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 80, egRate3: 80, egRate4: 85,
                egLevel1: 99, egLevel2: 99, egLevel3: 99, egLevel4: 0
            ),
            // OP4: 5th+octave (2 2/3')
            DX7OperatorPreset(
                outputLevel: 70, frequencyCoarse: 3, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 80, egRate3: 80, egRate4: 85,
                egLevel1: 99, egLevel2: 99, egLevel3: 99, egLevel4: 0
            ),
            // OP5: 2 octave (2')
            DX7OperatorPreset(
                outputLevel: 65, frequencyCoarse: 4, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 80, egRate3: 80, egRate4: 85,
                egLevel1: 99, egLevel2: 99, egLevel3: 99, egLevel4: 0
            ),
            // OP6 (feedback): percussive click
            DX7OperatorPreset(
                outputLevel: 60, frequencyCoarse: 8, frequencyFine: 0, detune: 7,
                feedback: 4,
                egRate1: 99, egRate2: 85, egRate3: 85, egRate4: 88,
                egLevel1: 99, egLevel2: 55, egLevel3: 40, egLevel4: 0
            ),
        ],
        category: .organ
    )

    // MARK: - 7. MARIMBA

    /// Mallet percussion
    /// Algorithm 5: [6]->5 | 4->3 | 2->1 (3 carriers)
    public static let marimba = DX7Preset(
        name: "MARIMBA",
        algorithm: 4,
        feedback: 7,
        operators: [
            // OP1 (carrier): fundamental
            DX7OperatorPreset(
                outputLevel: 99, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 62, egRate3: 40, egRate4: 72,
                egLevel1: 99, egLevel2: 55, egLevel3: 20, egLevel4: 0
            ),
            // OP2 (modulator→OP1): attack transient
            DX7OperatorPreset(
                outputLevel: 80, frequencyCoarse: 4, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 85, egRate3: 60, egRate4: 70,
                egLevel1: 99, egLevel2: 15, egLevel3: 5, egLevel4: 0
            ),
            // OP3 (carrier): resonance body
            DX7OperatorPreset(
                outputLevel: 85, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 58, egRate3: 38, egRate4: 68,
                egLevel1: 99, egLevel2: 50, egLevel3: 15, egLevel4: 0
            ),
            // OP4 (modulator→OP3): overtone
            DX7OperatorPreset(
                outputLevel: 72, frequencyCoarse: 10, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 90, egRate3: 65, egRate4: 75,
                egLevel1: 99, egLevel2: 10, egLevel3: 3, egLevel4: 0
            ),
            // OP5 (carrier): sub resonance
            DX7OperatorPreset(
                outputLevel: 70, frequencyCoarse: 3, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 70, egRate3: 45, egRate4: 72,
                egLevel1: 99, egLevel2: 35, egLevel3: 10, egLevel4: 0
            ),
            // OP6 (modulator→OP5, feedback): stick noise
            DX7OperatorPreset(
                outputLevel: 60, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                feedback: 7,
                egRate1: 99, egRate2: 92, egRate3: 70, egRate4: 78,
                egLevel1: 99, egLevel2: 8, egLevel3: 2, egLevel4: 0
            ),
        ],
        category: .percussion
    )

    // MARK: - 8. HARPSICH 1

    /// Harpsichord — plucky keyboard
    /// Algorithm 5: [6]->5 | 4->3 | 2->1 (3 carriers)
    public static let harpsichord1 = DX7Preset(
        name: "HARPSICH 1",
        algorithm: 4,
        feedback: 6,
        operators: [
            // OP1 (carrier): main body
            DX7OperatorPreset(
                outputLevel: 99, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 40, egRate3: 28, egRate4: 62,
                egLevel1: 99, egLevel2: 65, egLevel3: 40, egLevel4: 0
            ),
            // OP2 (modulator→OP1): pluck harmonics
            DX7OperatorPreset(
                outputLevel: 85, frequencyCoarse: 2, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 72, egRate3: 45, egRate4: 65,
                egLevel1: 99, egLevel2: 30, egLevel3: 10, egLevel4: 0
            ),
            // OP3 (carrier): octave shimmer
            DX7OperatorPreset(
                outputLevel: 82, frequencyCoarse: 2, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 45, egRate3: 30, egRate4: 65,
                egLevel1: 99, egLevel2: 60, egLevel3: 35, egLevel4: 0
            ),
            // OP4 (modulator→OP3): brightness
            DX7OperatorPreset(
                outputLevel: 78, frequencyCoarse: 5, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 78, egRate3: 50, egRate4: 68,
                egLevel1: 99, egLevel2: 20, egLevel3: 8, egLevel4: 0
            ),
            // OP5 (carrier): twang
            DX7OperatorPreset(
                outputLevel: 75, frequencyCoarse: 1, frequencyFine: 0, detune: 6,
                egRate1: 99, egRate2: 38, egRate3: 25, egRate4: 60,
                egLevel1: 99, egLevel2: 55, egLevel3: 30, egLevel4: 0
            ),
            // OP6 (modulator→OP5, feedback): attack bite
            DX7OperatorPreset(
                outputLevel: 70, frequencyCoarse: 3, frequencyFine: 0, detune: 7,
                feedback: 6,
                egRate1: 99, egRate2: 80, egRate3: 55, egRate4: 70,
                egLevel1: 99, egLevel2: 15, egLevel3: 5, egLevel4: 0
            ),
        ],
        category: .keys
    )

    // MARK: - 9. FLUTE 1

    /// Breathy flute
    /// Algorithm 4: [6]->5->4 | 3->2->1 (2 carriers, cross-fb on Alg4)
    public static let flute1 = DX7Preset(
        name: "FLUTE 1",
        algorithm: 3,
        feedback: 7,
        operators: [
            // OP1 (carrier): fundamental tone
            DX7OperatorPreset(
                outputLevel: 99, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 55, egRate2: 35, egRate3: 28, egRate4: 52,
                egLevel1: 99, egLevel2: 95, egLevel3: 92, egLevel4: 0
            ),
            // OP2 (modulator→OP1): breath modulation
            DX7OperatorPreset(
                outputLevel: 60, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 50, egRate2: 32, egRate3: 25, egRate4: 48,
                egLevel1: 99, egLevel2: 55, egLevel3: 40, egLevel4: 0
            ),
            // OP3 (modulator→OP2→OP1): overtone shaping
            DX7OperatorPreset(
                outputLevel: 45, frequencyCoarse: 2, frequencyFine: 0, detune: 7,
                egRate1: 48, egRate2: 30, egRate3: 22, egRate4: 45,
                egLevel1: 99, egLevel2: 40, egLevel3: 25, egLevel4: 0
            ),
            // OP4 (carrier): air/octave
            DX7OperatorPreset(
                outputLevel: 82, frequencyCoarse: 2, frequencyFine: 0, detune: 7,
                egRate1: 52, egRate2: 33, egRate3: 26, egRate4: 50,
                egLevel1: 99, egLevel2: 90, egLevel3: 85, egLevel4: 0
            ),
            // OP5 (modulator→OP4): breathy noise
            DX7OperatorPreset(
                outputLevel: 55, frequencyCoarse: 1, frequencyFine: 0, detune: 8,
                egRate1: 45, egRate2: 28, egRate3: 20, egRate4: 42,
                egLevel1: 99, egLevel2: 50, egLevel3: 35, egLevel4: 0
            ),
            // OP6 (modulator→OP5, feedback): air turbulence
            DX7OperatorPreset(
                outputLevel: 40, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                feedback: 7,
                egRate1: 40, egRate2: 25, egRate3: 18, egRate4: 38,
                egLevel1: 99, egLevel2: 35, egLevel3: 20, egLevel4: 0
            ),
        ],
        category: .woodwind
    )

    // MARK: - 10. CLAV 1

    /// Funky clavinet
    /// Algorithm 5: [6]->5 | 4->3 | 2->1 (3 carriers)
    public static let clav1 = DX7Preset(
        name: "CLAV 1",
        algorithm: 4,
        feedback: 6,
        operators: [
            // OP1 (carrier): main tone
            DX7OperatorPreset(
                outputLevel: 99, frequencyCoarse: 1, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 50, egRate3: 32, egRate4: 68,
                egLevel1: 99, egLevel2: 60, egLevel3: 35, egLevel4: 0
            ),
            // OP2 (modulator→OP1): string buzz
            DX7OperatorPreset(
                outputLevel: 88, frequencyCoarse: 3, frequencyFine: 50, detune: 7,
                egRate1: 99, egRate2: 75, egRate3: 48, egRate4: 65,
                egLevel1: 99, egLevel2: 35, egLevel3: 15, egLevel4: 0
            ),
            // OP3 (carrier): attack punch
            DX7OperatorPreset(
                outputLevel: 85, frequencyCoarse: 2, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 55, egRate3: 35, egRate4: 70,
                egLevel1: 99, egLevel2: 55, egLevel3: 30, egLevel4: 0
            ),
            // OP4 (modulator→OP3): pick attack
            DX7OperatorPreset(
                outputLevel: 82, frequencyCoarse: 6, frequencyFine: 0, detune: 7,
                egRate1: 99, egRate2: 88, egRate3: 55, egRate4: 72,
                egLevel1: 99, egLevel2: 15, egLevel3: 5, egLevel4: 0
            ),
            // OP5 (carrier): metallic ring
            DX7OperatorPreset(
                outputLevel: 70, frequencyCoarse: 1, frequencyFine: 0, detune: 6,
                egRate1: 99, egRate2: 45, egRate3: 28, egRate4: 65,
                egLevel1: 99, egLevel2: 50, egLevel3: 25, egLevel4: 0
            ),
            // OP6 (modulator→OP5, feedback): grit/distortion
            DX7OperatorPreset(
                outputLevel: 75, frequencyCoarse: 2, frequencyFine: 0, detune: 7,
                feedback: 6,
                egRate1: 99, egRate2: 82, egRate3: 52, egRate4: 68,
                egLevel1: 99, egLevel2: 20, egLevel3: 8, egLevel4: 0
            ),
        ],
        category: .keys
    )
}
