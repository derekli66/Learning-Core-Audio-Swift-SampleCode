//
//  main.swift
//  CH07_AUGraphSineWave-Swfit
//
//  Created by LEE CHIEN-MING on 21/04/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import AudioToolbox

private let sineFrequency: Double = 2200.0

class MySineWavePlayer
{
    var outputUnit: AudioUnit?
    var startingFrameCount: Double = 0.0
}

// MARK: Callback functions
private let SineWaveRenderProc: AURenderCallback = {
    (inRefCon: UnsafeMutableRawPointer,
     ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
     inTimeStamp: UnsafePointer<AudioTimeStamp>,
     inBusNumber: UInt32,
     inNumberFrames: UInt32,
     ioData: UnsafeMutablePointer<AudioBufferList>?) in
    
    var player = Unmanaged<MySineWavePlayer>.fromOpaque(inRefCon).takeUnretainedValue()
        
    var j = player.startingFrameCount
    let cycleLength = 44100.0 / sineFrequency
    
    guard let ioData_ = ioData else {
        debugPrint("No ioData for further processing")
        return kAudioUnitErr_InvalidOfflineRender
    }
    
    let abl = UnsafeMutableAudioBufferListPointer(ioData_)
    
    for frame in 0..<Int(inNumberFrames) {
        let buffer1 = abl[0]
        let buffer2 = abl[1]
        
        let capacity: Int = Int(buffer1.mDataByteSize / UInt32(MemoryLayout<Float32>.size))
        let frameData: Float32 = Float32(sin(2 * Double.pi * (j / cycleLength)))
        
        if let data = abl[0].mData {
            var float32Data = data.bindMemory(to: Float32.self, capacity: capacity)
            float32Data[frame] = frameData
        }
        
        if let data = abl[1].mData {
            var float32Data = data.bindMemory(to: Float32.self, capacity: capacity)
            float32Data[frame] = frameData
        }
        
        j += 1.0
        if (j > cycleLength) {
            j -= cycleLength
        }
    }
    
    player.startingFrameCount = j
    
    return noErr
}

func CreateAndConnectOutputUnit(with player: inout MySineWavePlayer) -> Void
{
    var outputcd: AudioComponentDescription = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                                        componentSubType: kAudioUnitSubType_DefaultOutput,
                                                                        componentManufacturer: kAudioUnitManufacturer_Apple,
                                                                        componentFlags: 0,
                                                                        componentFlagsMask: 0)
    let compOptional: AudioComponent? = AudioComponentFindNext(nil, &outputcd)
    guard let comp = compOptional else {
        debugPrint("Cannot get output unit")
        exit(-1)
    }
    
    CheckError(AudioComponentInstanceNew(comp, &player.outputUnit),
               "Couldn't open component for outputUnit")
    
    // registre render callback
    var input: AURenderCallbackStruct = AURenderCallbackStruct(inputProc: SineWaveRenderProc,
                                                               inputProcRefCon: Unmanaged.passUnretained(player).toOpaque())
    guard let outputUnit = player.outputUnit else {
        debugPrint("Cannot get output unit for setting render callback")
        exit(0)
    }
    
    // register render callback
    AudioUnitSetProperty(outputUnit,
                         kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Input,
                         0,
                         &input,
                         UInt32(MemoryLayout.size(ofValue: input)))
    
    // initialize unit
    CheckError(AudioUnitInitialize(outputUnit), "Couldn't initialize output unit")
}

// Start to play sine wave
var player: MySineWavePlayer = MySineWavePlayer()

// set up unit and callback 
CreateAndConnectOutputUnit(with: &player)

guard let outputUnit = player.outputUnit else {
    debugPrint("Couldn't start output unit")
    exit(0)
}

CheckError(AudioOutputUnitStart(outputUnit), "Couldn't start output unit")

debugPrint("[SineWave] playing")

// play for 5 seconds
sleep(5)

AudioOutputUnitStop(outputUnit)
AudioUnitUninitialize(outputUnit)
AudioComponentInstanceDispose(outputUnit)



