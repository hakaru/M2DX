#ifndef M2DXKernel_hpp
#define M2DXKernel_hpp

#include "DX7Constants.hpp"
#include "FMOperator.hpp"
#include <array>
#include <cstdint>
#include <algorithm>

namespace M2DX {

// Use DX7 constants for consistency
using DX7::kNumOperators;
using DX7::kMaxVoices;
using DX7::kNumAlgorithms;

/// MIDI note with velocity
struct MIDINote {
    uint8_t note = 0;
    uint8_t velocity = 0;
    bool active = false;
};

/// Single polyphonic voice with 6 FM operators (DX7 compatible)
class Voice {
public:
    void setSampleRate(float sampleRate) {
        for (auto& op : operators_) {
            op.setSampleRate(sampleRate);
        }
    }

    void setAlgorithm(int algorithm) {
        algorithm_ = std::clamp(algorithm, 0, kNumAlgorithms - 1);
    }

    void noteOn(uint8_t note, uint8_t velocity) {
        note_.note = note;
        note_.velocity = velocity;
        note_.active = true;

        float frequency = 440.0f * std::pow(2.0f, (note - 69) / 12.0f);
        float velocityScale = velocity / 127.0f;

        for (auto& op : operators_) {
            op.noteOn(frequency);
        }
        velocityScale_ = velocityScale;
    }

    void noteOff() {
        for (auto& op : operators_) {
            op.noteOff();
        }
    }

    float process() {
        if (!isActive()) return 0.0f;

        return processAlgorithm();
    }

    bool isActive() const {
        for (const auto& op : operators_) {
            if (op.isActive()) return true;
        }
        note_.active = false;
        return false;
    }

    uint8_t getNote() const { return note_.note; }

    FMOperator& getOperator(int index) {
        return operators_[std::clamp(index, 0, kNumOperators - 1)];
    }

private:
    /// Process based on current algorithm
    /// DX7 compatible: Algorithms 1-32 (6 operators)
    /// Future: Algorithms 33-64 for 8-operator extended mode
    float processAlgorithm() {
        float output = 0.0f;

        // DX7 Algorithm implementations
        // Currently implementing representative algorithms
        // TODO: Implement all 32 DX7 algorithms
        switch (algorithm_) {
            case 0: // Algorithm 1: Serial chain OP6->5->4->3->2->1 (carriers: OP1)
                output = processAlgorithm1();
                break;

            case 1: // Algorithm 2: OP6->5->4->3->2 + OP1 (carriers: OP1, OP2)
                output = processAlgorithm2();
                break;

            case 4: // Algorithm 5: Parallel pairs
                output = processAlgorithm5();
                break;

            case 31: // Algorithm 32: All parallel (carriers: all 6)
                output = processAlgorithm32();
                break;

            default:
                // Default to algorithm 1 for unimplemented
                output = processAlgorithm1();
                break;
        }

        return output * velocityScale_;
    }

    // DX7 Algorithm 1: OP6->5->4->3->2->1 (serial)
    float processAlgorithm1() {
        float mod = operators_[5].process(); // OP6
        mod = operators_[4].process(mod);    // OP5
        mod = operators_[3].process(mod);    // OP4
        mod = operators_[2].process(mod);    // OP3
        mod = operators_[1].process(mod);    // OP2
        return operators_[0].process(mod);   // OP1 (carrier)
    }

    // DX7 Algorithm 2: (OP6->5->4->3->2) + OP1
    float processAlgorithm2() {
        float mod = operators_[5].process(); // OP6
        mod = operators_[4].process(mod);    // OP5
        mod = operators_[3].process(mod);    // OP4
        mod = operators_[2].process(mod);    // OP3
        float out1 = operators_[1].process(mod);  // OP2 (carrier)
        float out2 = operators_[0].process();     // OP1 (carrier)
        return (out1 + out2) * 0.5f;
    }

    // DX7 Algorithm 5: Parallel pairs (OP6->5, OP4->3, OP2->1)
    float processAlgorithm5() {
        float mod1 = operators_[5].process();     // OP6
        float out1 = operators_[4].process(mod1); // OP5 (carrier)

        float mod2 = operators_[3].process();     // OP4
        float out2 = operators_[2].process(mod2); // OP3 (carrier)

        float mod3 = operators_[1].process();     // OP2
        float out3 = operators_[0].process(mod3); // OP1 (carrier)

        return (out1 + out2 + out3) * 0.33f;
    }

    // DX7 Algorithm 32: All carriers parallel
    float processAlgorithm32() {
        float output = 0.0f;
        for (int i = 0; i < kNumOperators; ++i) {
            output += operators_[i].process();
        }
        return output / static_cast<float>(kNumOperators);
    }

    std::array<FMOperator, kNumOperators> operators_;
    mutable MIDINote note_;
    int algorithm_ = 0;
    float velocityScale_ = 1.0f;
};

/// Main DSP kernel with polyphonic voice management
class M2DXKernel {
public:
    void initialize(float sampleRate) {
        sampleRate_ = sampleRate;
        for (auto& voice : voices_) {
            voice.setSampleRate(sampleRate);
            voice.setAlgorithm(algorithm_);
        }
    }

    void setAlgorithm(int algorithm) {
        algorithm_ = std::clamp(algorithm, 0, kNumAlgorithms - 1);
        for (auto& voice : voices_) {
            voice.setAlgorithm(algorithm_);
        }
    }

    void setMasterVolume(float volume) {
        masterVolume_ = std::clamp(volume, 0.0f, 1.0f);
    }

    /// Set operator parameter for all voices
    void setOperatorLevel(int opIndex, float level) {
        for (auto& voice : voices_) {
            voice.getOperator(opIndex).setLevel(level);
        }
    }

    void setOperatorRatio(int opIndex, float ratio) {
        for (auto& voice : voices_) {
            voice.getOperator(opIndex).setRatio(ratio);
        }
    }

    void setOperatorDetune(int opIndex, float detuneCents) {
        for (auto& voice : voices_) {
            voice.getOperator(opIndex).setDetune(detuneCents);
        }
    }

    void setOperatorFeedback(int opIndex, float feedback) {
        for (auto& voice : voices_) {
            voice.getOperator(opIndex).setFeedback(feedback);
        }
    }

    void setOperatorEnvelopeRates(int opIndex, float r1, float r2, float r3, float r4) {
        for (auto& voice : voices_) {
            voice.getOperator(opIndex).setEnvelopeRates(r1, r2, r3, r4);
        }
    }

    void setOperatorEnvelopeLevels(int opIndex, float l1, float l2, float l3, float l4) {
        for (auto& voice : voices_) {
            voice.getOperator(opIndex).setEnvelopeLevels(l1, l2, l3, l4);
        }
    }

    /// Handle MIDI note on
    void noteOn(uint8_t note, uint8_t velocity) {
        if (velocity == 0) {
            noteOff(note);
            return;
        }

        // Find free voice or steal oldest
        Voice* voice = findFreeVoice();
        if (voice) {
            voice->noteOn(note, velocity);
        }
    }

    /// Handle MIDI note off
    void noteOff(uint8_t note) {
        for (auto& voice : voices_) {
            if (voice.isActive() && voice.getNote() == note) {
                voice.noteOff();
            }
        }
    }

    /// All notes off
    void allNotesOff() {
        for (auto& voice : voices_) {
            voice.noteOff();
        }
    }

    /// Process single sample (mono)
    /// @return Normalized output sample with master volume applied
    ///
    /// Voice normalization:
    /// Uses sqrt(N) * 0.7 scaling to balance headroom and prevent clipping.
    /// The 0.7 factor compensates for typical voice stacking behavior,
    /// providing better perceived loudness without excessive level reduction.
    float processSample() {
        float output = 0.0f;
        int activeVoices = 0;

        for (auto& voice : voices_) {
            if (voice.isActive()) {
                output += voice.process();
                ++activeVoices;
            }
        }

        // DX7-style normalization with configurable curve
        // sqrt(N) provides better headroom than 1/N while avoiding clipping
        if (activeVoices > 0) {
            float normalization = std::sqrt(static_cast<float>(activeVoices)) * DX7::kVoiceNormalizationScale;
            output /= normalization;
        }

        return output * masterVolume_;
    }

    /// Process buffer (stereo interleaved)
    void processBuffer(float* outputL, float* outputR, int numFrames) {
        for (int i = 0; i < numFrames; ++i) {
            float sample = processSample();
            outputL[i] = sample;
            outputR[i] = sample;
        }
    }

    int getActiveVoiceCount() const {
        int count = 0;
        for (const auto& voice : voices_) {
            if (voice.isActive()) ++count;
        }
        return count;
    }

private:
    Voice* findFreeVoice() {
        // First, find an inactive voice
        for (auto& voice : voices_) {
            if (!voice.isActive()) {
                return &voice;
            }
        }

        // Voice stealing: return first voice (oldest)
        return &voices_[0];
    }

    std::array<Voice, kMaxVoices> voices_;
    float sampleRate_ = 44100.0f;
    float masterVolume_ = 0.7f;
    int algorithm_ = 0;
};

} // namespace M2DX

#endif /* M2DXKernel_hpp */
