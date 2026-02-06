#ifndef DX7Constants_hpp
#define DX7Constants_hpp

/// DX7 compatibility constants and parameter addresses
/// All constants related to DX7 specification are centralized here
/// to ensure consistency and maintainability across the codebase.

namespace M2DX {
namespace DX7 {

// ============================================================================
// MARK: - Operator Configuration
// ============================================================================

/// Number of FM operators (DX7 compatible: 6 operators)
constexpr int kNumOperators = 6;

/// Number of DX7 algorithms (32 standard algorithms, 0-31)
constexpr int kNumAlgorithms = 32;

// ============================================================================
// MARK: - Voice Management
// ============================================================================

/// Maximum number of polyphonic voices
constexpr int kMaxVoices = 16;

// ============================================================================
// MARK: - Envelope Constants
// ============================================================================

/// Maximum envelope rate value (DX7: 0-99)
constexpr float kEnvelopeMaxRate = 99.0f;

/// Maximum envelope level value (normalized: 0.0-1.0)
constexpr float kEnvelopeMaxLevel = 1.0f;

/// Number of envelope stages (Attack, Decay1, Decay2, Release)
constexpr int kEnvelopeStages = 4;

// ============================================================================
// MARK: - Feedback Constants
// ============================================================================

/// Maximum feedback value (DX7: 0-7, normalized to 0.0-1.0)
constexpr float kMaxFeedback = 1.0f;

/// Number of samples to average for feedback stability (DX7/Dexed: 2)
constexpr int kFeedbackAverageSamples = 2;

// ============================================================================
// MARK: - Voice Normalization
// ============================================================================

/// Voice normalization scale factor
/// sqrt(N) normalization with 0.7 compensation for voice stacking
constexpr float kVoiceNormalizationScale = 0.7f;

// ============================================================================
// MARK: - Parameter Address Structure
// ============================================================================

/// Base address for global parameters
constexpr int kGlobalAddressBase = 0;

/// Base address for operator parameters (operator 1 starts at 100)
constexpr int kOperatorAddressBase = 100;

/// Address stride between operators (each operator occupies 100 addresses)
constexpr int kOperatorAddressStride = 100;

// ============================================================================
// MARK: - Parameter Offsets within Operator Block
// ============================================================================

/// Offset for operator level parameter (0-99 in DX7, 0.0-1.0 normalized)
constexpr int kOperatorLevelOffset = 0;

/// Offset for operator frequency ratio (0.5-32.0)
constexpr int kOperatorRatioOffset = 1;

/// Offset for operator detune in cents (-100 to +100)
constexpr int kOperatorDetuneOffset = 2;

/// Offset for operator feedback amount (0.0-1.0)
constexpr int kOperatorFeedbackOffset = 3;

/// Base offset for envelope rates (4 rates: R1-R4 at offsets 10-13)
constexpr int kOperatorEGRateOffset = 10;

/// Base offset for envelope levels (4 levels: L1-L4 at offsets 20-23)
constexpr int kOperatorEGLevelOffset = 20;

// ============================================================================
// MARK: - Global Parameter Addresses
// ============================================================================

/// Address for algorithm selection (0-31)
constexpr int kAlgorithmAddress = 0;

/// Address for master volume (0.0-1.0)
constexpr int kMasterVolumeAddress = 1;

/// Address for global feedback (reserved, currently per-operator)
constexpr int kGlobalFeedbackAddress = 2;

// ============================================================================
// MARK: - Helper Functions
// ============================================================================

/// Calculate parameter address for operator-specific parameter
/// @param operatorIndex Operator index (0-5 for 6 operators)
/// @param offset Parameter offset within operator block
/// @return Absolute parameter address
constexpr int getOperatorParameterAddress(int operatorIndex, int offset) {
    return kOperatorAddressBase + (operatorIndex * kOperatorAddressStride) + offset;
}

/// Calculate address for operator level parameter
/// @param operatorIndex Operator index (0-5)
/// @return Parameter address for operator level
constexpr int getOperatorLevelAddress(int operatorIndex) {
    return getOperatorParameterAddress(operatorIndex, kOperatorLevelOffset);
}

/// Calculate address for operator ratio parameter
/// @param operatorIndex Operator index (0-5)
/// @return Parameter address for operator ratio
constexpr int getOperatorRatioAddress(int operatorIndex) {
    return getOperatorParameterAddress(operatorIndex, kOperatorRatioOffset);
}

/// Calculate address for operator detune parameter
/// @param operatorIndex Operator index (0-5)
/// @return Parameter address for operator detune
constexpr int getOperatorDetuneAddress(int operatorIndex) {
    return getOperatorParameterAddress(operatorIndex, kOperatorDetuneOffset);
}

/// Calculate address for operator feedback parameter
/// @param operatorIndex Operator index (0-5)
/// @return Parameter address for operator feedback
constexpr int getOperatorFeedbackAddress(int operatorIndex) {
    return getOperatorParameterAddress(operatorIndex, kOperatorFeedbackOffset);
}

/// Calculate address for operator envelope rate
/// @param operatorIndex Operator index (0-5)
/// @param rateIndex Rate index (0-3 for R1-R4)
/// @return Parameter address for envelope rate
constexpr int getOperatorEGRateAddress(int operatorIndex, int rateIndex) {
    return getOperatorParameterAddress(operatorIndex, kOperatorEGRateOffset + rateIndex);
}

/// Calculate address for operator envelope level
/// @param operatorIndex Operator index (0-5)
/// @param levelIndex Level index (0-3 for L1-L4)
/// @return Parameter address for envelope level
constexpr int getOperatorEGLevelAddress(int operatorIndex, int levelIndex) {
    return getOperatorParameterAddress(operatorIndex, kOperatorEGLevelOffset + levelIndex);
}

} // namespace DX7
} // namespace M2DX

#endif /* DX7Constants_hpp */
