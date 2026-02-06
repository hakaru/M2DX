#ifndef M2DXKernelBridge_h
#define M2DXKernelBridge_h

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C wrapper for M2DX C++ DSP Kernel
@interface M2DXKernelBridge : NSObject

/// Initialize with sample rate
- (instancetype)initWithSampleRate:(double)sampleRate;

/// Update sample rate
- (void)setSampleRate:(double)sampleRate;

/// Set algorithm (0-63)
- (void)setAlgorithm:(int)algorithm;

/// Set master volume (0.0-1.0)
- (void)setMasterVolume:(float)volume;

/// Set operator level (0.0-1.0)
- (void)setOperatorLevel:(int)operatorIndex level:(float)level;

/// Set operator frequency ratio
- (void)setOperatorRatio:(int)operatorIndex ratio:(float)ratio;

/// Set operator detune in cents
- (void)setOperatorDetune:(int)operatorIndex detuneCents:(float)cents;

/// Set operator feedback (0.0-1.0)
- (void)setOperatorFeedback:(int)operatorIndex feedback:(float)feedback;

/// Set operator envelope rates (DX7 style 0-99)
- (void)setOperatorEnvelopeRates:(int)operatorIndex r1:(float)r1 r2:(float)r2 r3:(float)r3 r4:(float)r4;

/// Set operator envelope levels (0.0-1.0)
- (void)setOperatorEnvelopeLevels:(int)operatorIndex l1:(float)l1 l2:(float)l2 l3:(float)l3 l4:(float)l4;

/// Handle MIDI note on
- (void)handleNoteOn:(uint8_t)note velocity:(uint8_t)velocity NS_SWIFT_NAME(handleNoteOn(_:velocity:));

/// Handle MIDI note off
- (void)handleNoteOff:(uint8_t)note NS_SWIFT_NAME(handleNoteOff(_:));

/// All notes off
- (void)allNotesOff;

/// Process audio buffer (stereo)
- (void)processBufferLeft:(float *)outputL right:(float *)outputR frameCount:(int)frameCount;

/// Get current active voice count
- (int)activeVoiceCount;

@end

NS_ASSUME_NONNULL_END

#endif /* M2DXKernelBridge_h */
