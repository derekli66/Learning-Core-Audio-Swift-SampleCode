//
//  CARingBuffer_Wrapper.hpp
//  CH08-AUGraphInput
//
//  Created by LEE CHIEN-MING on 16/05/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

#ifndef CARingBuffer_Wrapper_h
#define CARingBuffer_Wrapper_h

#include <stdio.h>
#import <AudioToolbox/AudioToolbox.h>

typedef SInt64 SampleTime;
typedef SInt32 CARingBufferError;

#if __cplusplus
extern "C" {
#endif
typedef struct RingBufferWrapper {
    void *ringBufferPtr;
}RingBufferWrapper;

RingBufferWrapper CreateRingBuffer();

void DestroyBuffer(RingBufferWrapper wrapper);
    
void AllocateBuffer(RingBufferWrapper wrapper, int nChannels, UInt32 bytesPerFrame, UInt32 capacityFrames);
    
void DeallocateBuffer(RingBufferWrapper wrapper);
    
CARingBufferError StoreBuffer(RingBufferWrapper wrapper, const AudioBufferList *abl, UInt32 nFrames, SampleTime frameNumber);
    
CARingBufferError FetchBuffer(RingBufferWrapper wrapper, AudioBufferList *abl, UInt32 nFrames, SampleTime frameNumber);
    
CARingBufferError GetTimeBoundsFromBuffer(RingBufferWrapper wrapper, SampleTime *startTime, SampleTime *endTime);
#if __cplusplus
}
#endif

#endif /* CARingBuffer_Wrapper_hpp */
