#import "M2DXKernelBridge.h"
#include "../DSP/M2DXKernel.hpp"
#include <memory>

@implementation M2DXKernelBridge {
    std::unique_ptr<M2DX::M2DXKernel> _kernel;
}

- (instancetype)initWithSampleRate:(double)sampleRate {
    self = [super init];
    if (self) {
        _kernel = std::make_unique<M2DX::M2DXKernel>();
        _kernel->initialize(static_cast<float>(sampleRate));

        // Set default operator parameters for a basic FM piano-like sound
        // DX7 compatible: 6 operators
        for (int i = 0; i < 6; ++i) {
            _kernel->setOperatorLevel(i, (i < 4) ? 1.0f : 0.5f);
            _kernel->setOperatorRatio(i, static_cast<float>(i + 1));
            _kernel->setOperatorDetune(i, 0.0f);
            _kernel->setOperatorFeedback(i, (i == 5) ? 0.3f : 0.0f);
            _kernel->setOperatorEnvelopeRates(i, 99.0f, 75.0f, 50.0f, 50.0f);
            _kernel->setOperatorEnvelopeLevels(i, 1.0f, 0.8f, 0.6f, 0.0f);
        }
    }
    return self;
}

- (void)setSampleRate:(double)sampleRate {
    _kernel->initialize(static_cast<float>(sampleRate));
}

- (void)setAlgorithm:(int)algorithm {
    _kernel->setAlgorithm(algorithm);
}

- (void)setMasterVolume:(float)volume {
    _kernel->setMasterVolume(volume);
}

- (void)setOperatorLevel:(int)operatorIndex level:(float)level {
    _kernel->setOperatorLevel(operatorIndex, level);
}

- (void)setOperatorRatio:(int)operatorIndex ratio:(float)ratio {
    _kernel->setOperatorRatio(operatorIndex, ratio);
}

- (void)setOperatorDetune:(int)operatorIndex detuneCents:(float)cents {
    _kernel->setOperatorDetune(operatorIndex, cents);
}

- (void)setOperatorFeedback:(int)operatorIndex feedback:(float)feedback {
    _kernel->setOperatorFeedback(operatorIndex, feedback);
}

- (void)setOperatorEnvelopeRates:(int)operatorIndex r1:(float)r1 r2:(float)r2 r3:(float)r3 r4:(float)r4 {
    _kernel->setOperatorEnvelopeRates(operatorIndex, r1, r2, r3, r4);
}

- (void)setOperatorEnvelopeLevels:(int)operatorIndex l1:(float)l1 l2:(float)l2 l3:(float)l3 l4:(float)l4 {
    _kernel->setOperatorEnvelopeLevels(operatorIndex, l1, l2, l3, l4);
}

- (void)handleNoteOn:(uint8_t)note velocity:(uint8_t)velocity {
    _kernel->noteOn(note, velocity);
}

- (void)handleNoteOff:(uint8_t)note {
    _kernel->noteOff(note);
}

- (void)allNotesOff {
    _kernel->allNotesOff();
}

- (void)processBufferLeft:(float *)outputL right:(float *)outputR frameCount:(int)frameCount {
    _kernel->processBuffer(outputL, outputR, frameCount);
}

- (int)activeVoiceCount {
    return _kernel->getActiveVoiceCount();
}

@end
