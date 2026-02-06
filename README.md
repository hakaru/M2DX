# M2DX
### MIDI 2.0 FM Synth Reference

> **Bringing legendary FM sound into 21st-century resolution with MIDI2Kit**

**M2DX** is a next-generation FM synthesizer reference implementation,
faithfully reproducing classic DX-style FM synthesis while being designed **from the ground up for MIDI 2.0**.

This project demonstrates how **MIDI2Kit**, **Property Exchange**, and **32-bit UMP control**
fundamentally change the way complex instruments are built, controlled, and understood.

M2DX is not just a synth —
it is a **living specification and showcase** for modern MIDI.

---

## ✨ Key Features

### 🔁 Full Bidirectional Editing (Property Exchange)
- Over **155 DX7-style parameters** exposed as a hierarchical Property Exchange tree
- Parameters appear automatically in DAWs and controllers as:
  ```
  Operators/Op1/Level
  Operators/Op6/Ratio
  LFO/Wave
  Global/Algorithm
  ```
- No manual mapping, no hidden SysEx
- A fully **self-describing instrument**

---

### 🎚 32-bit High-Resolution FM Control (MIDI 2.0 UMP)
- Eliminates the classic "stepped" sound changes caused by 7-bit MIDI
- Operator levels, feedback, and modulation are controlled with **32-bit precision**
- Smooth, continuous FM modulation — finally audible

> FM synthesis was never the problem.
> Control resolution was.

---

### 📦 JSON-Based Preset Management
- Presets are handled via **Property Exchange JSON**, not binary SysEx
- Enables:
  - Text-based patch inspection
  - Tagging and searching
  - Parameter-level diff and partial transfer
- Designed for future cloud-based workflows

---

## 🧠 Architecture Overview

### DSP Engine
- Written in **C++**
- Faithful DX-style algorithms and envelope behavior
- **6 operators** (DX7 compatible) — 8-operator extension planned for future
- 32 classic DX7 algorithms
- Packaged as **AUv3** (Audio Unit v3 Extension)

### MIDI / Control Layer
- Implemented in **Swift** using **MIDI2Kit**
- Native support for:
  - MIDI 2.0 UMP
  - Property Exchange (PE)

### UI / UX
- AUv3 interface built with SwiftUI
- All **6 operators** visible at all times (2×3 grid layout)
- Algorithm and modulation flow visually represented
- TX816 multi-timbral mode planned for future
- Designed to make FM synthesis *understandable*

---

## 🎯 Project Goals

M2DX exists as a **flagship reference project for MIDI2Kit**.

It answers practical questions such as:
- How should large parameter sets be modeled for Property Exchange?
- How does a DAW "discover" an instrument without manual setup?
- What does MIDI 2.0 actually sound like in real instruments?

M2DX provides **code, sound, and structure** — not just documentation.

---

## 🧩 Intended Use Cases

- MIDI2Kit / MIDI 2.0 reference implementation
- DAW and MIDI controller development demos
- FM synthesis UX exploration
- Technical articles, talks, and educational material

---

## 📎 Project Status

- Visual design & UI mockups: ✅
- 6-operator DX7 compatible model: ✅
- Property Exchange design: ✅
- DSP implementation: In progress
- AUv3 Audio Unit Extension: ✅
- 8-operator extension: Planned

---

## 🏷 Keywords

`MIDI 2.0` · `MIDI2Kit` · `Property Exchange` · `FM Synthesis` · `DX7`
`AUv3` · `High-Resolution Control` · `6-Operator`
