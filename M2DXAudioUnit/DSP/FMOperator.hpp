#ifndef FMOperator_hpp
#define FMOperator_hpp

#include "DX7Constants.hpp"
#include <cmath>
#include <cstdint>

namespace M2DX {

/// DX7-style envelope generator with 4 rates and 4 levels
class Envelope {
public:
    enum class Stage {
        Idle,
        Attack,   // R1 -> L1
        Decay1,   // R2 -> L2
        Decay2,   // R3 -> L3
        Sustain,  // Hold at L3
        Release   // R4 -> L4 (usually 0)
    };

    void setRates(float r1, float r2, float r3, float r4) {
        rates_[0] = r1; rates_[1] = r2;
        rates_[2] = r3; rates_[3] = r4;
        recalculateCoefficients();
    }

    void setLevels(float l1, float l2, float l3, float l4) {
        levels_[0] = l1; levels_[1] = l2;
        levels_[2] = l3; levels_[3] = l4;
    }

    void setSampleRate(float sampleRate) {
        sampleRate_ = sampleRate;
        recalculateCoefficients();
    }

    void noteOn() {
        stage_ = Stage::Attack;
        currentLevel_ = 0.0f;
    }

    void noteOff() {
        if (stage_ != Stage::Idle) {
            stage_ = Stage::Release;
        }
    }

    float process() {
        switch (stage_) {
            case Stage::Idle:
                return 0.0f;

            case Stage::Attack:
                currentLevel_ += coefficients_[0] * (levels_[0] - currentLevel_);
                if (currentLevel_ >= levels_[0] * 0.99f) {
                    currentLevel_ = levels_[0];
                    stage_ = Stage::Decay1;
                }
                break;

            case Stage::Decay1:
                currentLevel_ += coefficients_[1] * (levels_[1] - currentLevel_);
                if (std::abs(currentLevel_ - levels_[1]) < 0.001f) {
                    currentLevel_ = levels_[1];
                    stage_ = Stage::Decay2;
                }
                break;

            case Stage::Decay2:
                currentLevel_ += coefficients_[2] * (levels_[2] - currentLevel_);
                if (std::abs(currentLevel_ - levels_[2]) < 0.001f) {
                    currentLevel_ = levels_[2];
                    stage_ = Stage::Sustain;
                }
                break;

            case Stage::Sustain:
                // Hold at L3
                break;

            case Stage::Release:
                currentLevel_ += coefficients_[3] * (levels_[3] - currentLevel_);
                if (currentLevel_ <= 0.001f) {
                    currentLevel_ = 0.0f;
                    stage_ = Stage::Idle;
                }
                break;
        }

        return currentLevel_;
    }

    bool isActive() const { return stage_ != Stage::Idle; }
    Stage getStage() const { return stage_; }

private:
    void recalculateCoefficients() {
        // Convert DX7 rate (0-99) to coefficient
        // Higher rate = faster envelope
        for (int i = 0; i < 4; ++i) {
            float rate = rates_[i];
            // DX7-style rate scaling
            float timeInSeconds = 10.0f * std::exp(-0.069f * rate);
            coefficients_[i] = 1.0f - std::exp(-1.0f / (timeInSeconds * sampleRate_));
        }
    }

    float sampleRate_ = 44100.0f;
    float rates_[4] = {99.0f, 75.0f, 50.0f, 50.0f};
    float levels_[4] = {1.0f, 0.8f, 0.7f, 0.0f};
    float coefficients_[4] = {0.01f, 0.001f, 0.001f, 0.001f};
    float currentLevel_ = 0.0f;
    Stage stage_ = Stage::Idle;
};

/// Single FM operator with sine oscillator and envelope
class FMOperator {
public:
    void setSampleRate(float sampleRate) {
        sampleRate_ = sampleRate;
        phaseIncrement_ = frequency_ / sampleRate_;
        envelope_.setSampleRate(sampleRate);
    }

    void setFrequency(float frequency) {
        frequency_ = frequency;
        phaseIncrement_ = frequency_ / sampleRate_;
    }

    void setRatio(float ratio) {
        ratio_ = ratio;
    }

    void setDetune(float detuneCents) {
        detune_ = std::pow(2.0f, detuneCents / 1200.0f);
    }

    void setLevel(float level) {
        level_ = level;
    }

    void setFeedback(float feedback) {
        feedback_ = feedback;
    }

    void setEnvelopeRates(float r1, float r2, float r3, float r4) {
        envelope_.setRates(r1, r2, r3, r4);
    }

    void setEnvelopeLevels(float l1, float l2, float l3, float l4) {
        envelope_.setLevels(l1, l2, l3, l4);
    }

    void noteOn(float baseFrequency) {
        frequency_ = baseFrequency * ratio_ * detune_;
        phaseIncrement_ = frequency_ / sampleRate_;
        envelope_.noteOn();
        phase_ = 0.0f;
        previousOutput_ = 0.0f;
        previousOutput2_ = 0.0f;
    }

    void noteOff() {
        envelope_.noteOff();
    }

    /// Process one sample with optional external modulation
    /// @param modulation External modulation input (phase modulation in cycles, typically -1 to +1)
    /// @return Output sample with envelope and level applied (-1.0 to +1.0)
    ///
    /// DX7 compatibility notes:
    /// - Uses 2-sample feedback averaging for stability (DX7/Dexed compatible)
    /// - Phase accumulation with wrap at 1.0
    /// - Sine oscillator with full envelope control
    /// - Self-feedback prevents aliasing at high feedback values
    float process(float modulation = 0.0f) {
        float envelopeLevel = envelope_.process();

        // DX7/Dexed-style 2-sample averaging for feedback stability
        // This prevents oscillation and aliasing at high feedback values
        float feedbackMod = feedback_ * (previousOutput_ + previousOutput2_) * 0.5f;

        // Calculate phase with modulation
        float effectivePhase = phase_ + modulation + feedbackMod;

        // Sine oscillator
        float output = std::sin(effectivePhase * 2.0f * M_PI);

        // Apply envelope and level
        output *= envelopeLevel * level_;

        // Update phase
        phase_ += phaseIncrement_;
        if (phase_ >= 1.0f) {
            phase_ -= 1.0f;
        }

        // Shift feedback history
        previousOutput2_ = previousOutput_;
        previousOutput_ = output;
        return output;
    }

    bool isActive() const { return envelope_.isActive(); }

    float getLevel() const { return level_; }
    float getRatio() const { return ratio_; }
    float getFeedback() const { return feedback_; }

private:
    float sampleRate_ = 44100.0f;
    float frequency_ = 440.0f;
    float ratio_ = 1.0f;
    float detune_ = 1.0f;
    float level_ = 1.0f;
    float feedback_ = 0.0f;
    float phase_ = 0.0f;
    float phaseIncrement_ = 0.0f;
    float previousOutput_ = 0.0f;
    float previousOutput2_ = 0.0f;  // Second sample for feedback averaging
    Envelope envelope_;
};

} // namespace M2DX

#endif /* FMOperator_hpp */
