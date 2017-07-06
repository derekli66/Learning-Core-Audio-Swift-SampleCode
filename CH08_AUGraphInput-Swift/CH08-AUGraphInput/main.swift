//
//  main.swift
//  CH08-AUGraphInput
//
//  Created by LEE CHIEN-MING on 16/05/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import AudioToolbox
import ApplicationServices

// MARK: - Audio
struct MyAUGraphPlayer
{
    var streamFormat: AudioStreamBasicDescription?
    var graph: AUGraph?
    var inputUnit: AudioUnit?
    var outputUnit: AudioUnit?
#if PART_II
    var speechUnit: AudioUnit?
#endif
    var inputBuffer: UnsafeMutableAudioBufferListPointer?
    var ringBuffer: RingBufferWrapper?
    
    var firstInputSampleTime: Float64 = 0.0
    var firstOutputSampleTime: Float64 = 0.0
    var inToOutSampleTimeOffset: Float64 = 0.0
}

let inputRenderProc: AURenderCallback = {
    (inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?) in
    
    debugPrint("InputRenderProc!")
    var player: MyAUGraphPlayer = inRefCon.bindMemory(to: MyAUGraphPlayer.self, capacity: 1).pointee
    
    // have we ever logged input timing? (for offset calculation)
    if (player.firstInputSampleTime < 0.0) {
        player.firstInputSampleTime = inTimeStamp.pointee.mSampleTime
        if (player.firstOutputSampleTime > -1.0) && (player.inToOutSampleTimeOffset < 0.0) {
            player.inToOutSampleTimeOffset = player.firstInputSampleTime - player.firstOutputSampleTime
        }
    }
  
    guard let inputUnit = player.inputUnit,
        let inputBuffer = player.inputBuffer,
        let ringBuffer = player.ringBuffer else {
        debugPrint("Could't get enough arguments for further process")
        return kAudioUnitErr_InvalidElement
    }
    
    // render into our buffer
    var inputProcErr: OSStatus = noErr
    inputProcErr = AudioUnitRender(inputUnit,
                                   ioActionFlags,
                                   inTimeStamp,
                                   inBusNumber,
                                   inNumberFrames,
                                   inputBuffer.unsafeMutablePointer)
    
    if (inputProcErr == noErr) {
        inputProcErr = StoreBuffer(ringBuffer,
                                   inputBuffer.unsafeMutablePointer,
                                   inNumberFrames,
                                   SampleTime(inTimeStamp.pointee.mSampleTime))
    }
    
    return inputProcErr
}

let graphRenderProc: AURenderCallback = {
    (inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?) in
    
    var player: MyAUGraphPlayer = inRefCon.bindMemory(to: MyAUGraphPlayer.self, capacity: 1).pointee
    var audioTimeStamp = inTimeStamp.pointee
    
    if (player.firstOutputSampleTime < 0.0) {
        player.firstOutputSampleTime = audioTimeStamp.mSampleTime
        if (player.firstInputSampleTime > -1.0 && player.inToOutSampleTimeOffset < 0.0) {
            player.inToOutSampleTimeOffset = player.firstInputSampleTime - player.firstOutputSampleTime
        }
    }
    
    // copy samples out of ring buffer
    var outputProcError: OSStatus = noErr
    outputProcError = FetchBuffer(player.ringBuffer!,
                                  ioData,
                                  inNumberFrames,
                                  SampleTime(audioTimeStamp.mSampleTime + player.inToOutSampleTimeOffset))
    
    debugPrint("fetched \(inNumberFrames) frames at time \(audioTimeStamp.mSampleTime)")
    return noErr
}

func CreateInputUnit(_ player: inout MyAUGraphPlayer)
{
    // generate description that will match audio HAL
    var inputcd = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                            componentSubType: kAudioUnitSubType_HALOutput,
                                            componentManufacturer: kAudioUnitManufacturer_Apple,
                                            componentFlags: 0,
                                            componentFlagsMask: 0)
    
    let component: AudioComponent? = AudioComponentFindNext(nil, &inputcd)
    guard let comp = component else {
        debugPrint("can't get output unit")
        exit(-1)
    }
    
    CheckError(AudioComponentInstanceNew(comp, &player.inputUnit),
               "Couldn't open component for inputUnit")
    
    guard let inputUnit = player.inputUnit else {
        debugPrint("Cannot get input unit for initialization")
        exit(-1)
    }
    
    // Enable IO 
    var disableFlag: UInt32 = 0
    var enableFlag: UInt32 = 1
    let outputBus: AudioUnitElement = 0
    let inputBus: AudioUnitElement = 1
    CheckError(AudioUnitSetProperty(inputUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Input,
                         inputBus,
                         &enableFlag,
                         UInt32(MemoryLayout.size(ofValue: enableFlag))), "Couldn't enable input on IO unit")
    
    CheckError(AudioUnitSetProperty(inputUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Output,
                         outputBus,
                         &disableFlag,
                         UInt32(MemoryLayout.size(ofValue: enableFlag))), "Couldn't disable output on I/O unit")
    
    // set device (osx only... iphone has only one device)
    var defaultDevice: AudioDeviceID = kAudioObjectUnknown
    var propertySize: UInt32 = UInt32(MemoryLayout.size(ofValue: defaultDevice))
    var defaultDeviceProperty = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                             mScope: kAudioObjectPropertyScopeGlobal,
                                                             mElement: kAudioObjectPropertyElementMaster)
    
    CheckError(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                           &defaultDeviceProperty ,
                                           0,
                                           nil,
                                           &propertySize,
                                           &defaultDevice), "Couldn't get default input device")
    
    // set this defaultDevice as the input's property
    // kAudioUnitErr_InvalidPropertyValue if output is enabled on inputUnit
    CheckError(AudioUnitSetProperty(inputUnit,
                         kAudioOutputUnitProperty_CurrentDevice,
                         kAudioUnitScope_Global,
                         outputBus,
                         &defaultDevice,
                         UInt32(MemoryLayout.size(ofValue: defaultDevice))),
                "Couldn't set default device on IO unit")
    
    // use the stream format coming out of the AUHAL (should be de-interleaved)
    propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var inputBusOutputFormat = AudioStreamBasicDescription()
    CheckError(AudioUnitGetProperty(inputUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Output,
                         inputBus,
                         &inputBusOutputFormat,
                         &propertySize), "Couldn't get ASBD from input unit")
    player.streamFormat = inputBusOutputFormat
    
    // check the input device's stream format
    var deviceFormat = AudioStreamBasicDescription()
    CheckError(AudioUnitGetProperty(inputUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         inputBus,
                         &deviceFormat,
                         &propertySize), "Couldn't get ASBD from input unit")
    
    debugPrint("Device rate \(deviceFormat.mSampleRate), graph rate \(String(describing: player.streamFormat?.mSampleRate))")
    player.streamFormat?.mSampleRate = deviceFormat.mSampleRate
    
    propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    CheckError(AudioUnitSetProperty(inputUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Output,
                         inputBus,
                         &player.streamFormat,
                         propertySize), "Couldn't set ASBD on input unit")
    
    guard let streamFormat = player.streamFormat else {
        debugPrint("Cannot get stream format to set up output unit")
        exit(-1)
    }
    
    // allocate some buffers to hold samples between input and output callbacks
    // Get the size of the IO buffers
    var bufferSizeFrames: UInt32 = 0
    propertySize = UInt32(MemoryLayout<UInt32>.size)
    CheckError(AudioUnitGetProperty(inputUnit,
                         kAudioDevicePropertyBufferFrameSize,
                         kAudioUnitScope_Global,
                         0,
                         &bufferSizeFrames,
                         &propertySize), "Couldn't get buffer frame size from input unit")
    let bufferSizeBytes = bufferSizeFrames * UInt32(MemoryLayout<Float32>.size)
    
    if (((player.streamFormat?.mFormatFlags)! & kAudioFormatFlagIsNonInterleaved) > 0) {
        let inputBuffer: UnsafeMutableAudioBufferListPointer = AudioBufferList.allocate(maximumBuffers: Int(streamFormat.mChannelsPerFrame))
        player.inputBuffer = inputBuffer
        
        for var audioBuffer in inputBuffer {
            audioBuffer.mNumberChannels = 1
            audioBuffer.mDataByteSize = bufferSizeBytes
            audioBuffer.mData = malloc(Int(bufferSizeBytes))
            memset(audioBuffer.mData, 0, Int(audioBuffer.mDataByteSize))
        }
    }
    else {
        debugPrint("format is interleaved")
        let inputBuffer: UnsafeMutableAudioBufferListPointer = AudioBufferList.allocate(maximumBuffers: 1)
        player.inputBuffer = inputBuffer
        
        player.inputBuffer?[0].mNumberChannels = streamFormat.mChannelsPerFrame
        player.inputBuffer?[0].mDataByteSize = bufferSizeBytes
        player.inputBuffer?[0].mData = malloc(Int(bufferSizeBytes))
        memset(player.inputBuffer?[0].mData, 0, Int(bufferSizeBytes))
    }
    
    // Allocate ring buffer that will hold data between the two audio devices
    player.ringBuffer = CreateRingBuffer()
    AllocateBuffer(player.ringBuffer!,
                   Int32(streamFormat.mChannelsPerFrame),
                   streamFormat.mBytesPerFrame,
                   bufferSizeFrames * 3)
    
    // set render proc to supply samples from input unit
    var callbackStruct = AURenderCallbackStruct(inputProc: inputRenderProc,
                                                inputProcRefCon: UnsafeMutablePointer(&player))
    
    CheckError(AudioUnitSetProperty(inputUnit,
                         kAudioOutputUnitProperty_SetInputCallback,
                         kAudioUnitScope_Global,
                         0,
                         &callbackStruct,
                         UInt32(MemoryLayout.size(ofValue: callbackStruct))),
               "Couldn't set input callback")
    
    CheckError(AudioUnitInitialize(inputUnit), "Couldn't initalize input unit")
    
    player.firstInputSampleTime = -1
    player.inToOutSampleTimeOffset = -1
    
    debugPrint("Bottom of CreateInputUnit()")
}

func CreateMyAUGraph(_ player: inout MyAUGraphPlayer) -> Void
{
    // Create a new AUGraph
    CheckError(NewAUGraph(&player.graph), "NewAUGraph failed")
    
    guard let audioGraph = player.graph else {
        debugPrint("Cannot get audio graph")
        exit(-1)
    }
    
    var outputcd = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                             componentSubType: kAudioUnitSubType_DefaultOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0,
                                             componentFlagsMask: 0)
    
    let comp = AudioComponentFindNext(nil, &outputcd)
    if comp == nil {
        debugPrint("Can't get output unit")
        exit(-1)
    }
    
    // Adds a node with above description to the graph
    var outputNode: AUNode = 0
    CheckError(AUGraphAddNode(audioGraph,
                   &outputcd,
                   &outputNode), "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed")
    
#if PART_II
    // Adds a mixer to the graph
    var mixercd = AudioComponentDescription(componentType: kAudioUnitType_Mixer,
                                            componentSubType: kAudioUnitSubType_StereoMixer,
                                            componentManufacturer: kAudioUnitManufacturer_Apple,
                                            componentFlags: 0,
                                            componentFlagsMask: 0)
    
    var mixerNode: AUNode = 0
    CheckError(AUGraphAddNode(audioGraph, &mixercd, &mixerNode),
               "AUGraphAddNode[kAudioUnitSubType_StereoMixer] failed")
    
    // Adds a node with above description to the graph
    var speechcd = AudioComponentDescription(componentType: kAudioUnitType_Generator,
                                             componentSubType: kAudioUnitSubType_SpeechSynthesis,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0,
                                             componentFlagsMask: 0)
    
    var speechNode: AUNode = 0
    CheckError(AUGraphAddNode(audioGraph, &speechcd, &speechNode),
               "AUGraphAddNode[kAudioUnitSubType_AudioFilePlayer] failed")
    
    // Opening the graph opens all contained audio units but does not allocate any resources yet
    CheckError(AUGraphOpen(audioGraph), "AUGraphOpen failed")
    
    
    // Get the reference to the AudioUnit objects for the various nodes
    CheckError(AUGraphNodeInfo(audioGraph,
                    outputNode,
                    nil,
                    &player.outputUnit), "AUGraphNodeInfo failed")
    CheckError(AUGraphNodeInfo(audioGraph,
                    speechNode,
                    nil,
                    &player.speechUnit), "AUGraphNodeInfo failed")
    
    var mixerUnit: AudioUnit?
    CheckError(AUGraphNodeInfo(audioGraph,
                    mixerNode,
                    nil,
                    &mixerUnit), "AUGraphNodeInfo failed")
    
    guard let mixerUnit_ = mixerUnit else {
        debugPrint("Cannot get mixer unit for audio graph")
        exit(-1)
    }
    
    // Set ASBDs here
    let propertySize: UInt32 = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    // Set stream format on input scope of bus 0 because of the render callback will be plug in at this scope
    CheckError(AudioUnitSetProperty(mixerUnit_,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         0,
                         &player.streamFormat,
                         propertySize), "Couldn't set stream format on mixer unit input scope of bus 0")
    
    // Set output stream format on speech unit and mixer unit to let stream format propagation happens
    CheckError(AudioUnitSetProperty(player.speechUnit!,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output,
                                    0,
                                    &player.streamFormat,
                                    propertySize), "Couldn't set stream format on speech unit bus 0")
    
    CheckError(AudioUnitSetProperty(mixerUnit_,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output,
                                    0,
                                    &player.streamFormat,
                                    propertySize), "Couldn't set stream format on mixer unit output scope of bus 0")
    
   	// connections
    // mixer output scope / bus 0 to outputUnit input scope / bus 0
    // mixer input scope / bus 0 to render callback (from ringbuffer, which in turn is from inputUnit)
    // mixer input scope / bus 1 to speech unit output scope / bus 0
    
    CheckError(AUGraphConnectNodeInput(audioGraph,
                            mixerNode,
                            0,
                            outputNode,
                            0), "Couldn't connect mixer output(0) to outputNode (0)")
    
    CheckError(AUGraphConnectNodeInput(audioGraph,
                            speechNode,
                            0,
                            mixerNode,
                            1), "Couldn't connect speech synth unit output (0) to mixer input (1)")
    
    let referencePtr = withUnsafeMutablePointer(to: &player, { return UnsafeMutableRawPointer($0) })
    var callbackStruct = AURenderCallbackStruct(inputProc: graphRenderProc,
                                                inputProcRefCon: referencePtr)
    
    AudioUnitSetProperty(mixerUnit_,
                         kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Global,
                         0,
                         &callbackStruct,
                         UInt32(MemoryLayout.size(ofValue: callbackStruct)))
#else
    
    // opening the graph opens all contained audio units but does not allocate any resources yet
    CheckError(AUGraphOpen(audioGraph), "AUGraphOpen failed")

    // get the reference to the AudioUnit object for the output graph node
    CheckError(AUGraphNodeInfo(audioGraph, outputNode, nil, &player.outputUnit), "AUGraphNodeInfo failed")
    
    // set the stream format on the output unit's input scope
    let propertySize: Int = MemoryLayout<AudioStreamBasicDescription>.size
    
    CheckError(AudioUnitSetProperty(player.outputUnit!,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         0,
                         &player.streamFormat,
                         UInt32(propertySize)), "Couldn't set stream format on output unit")
    
    let referencePtr = withUnsafeMutablePointer(to: &player, { return UnsafeMutableRawPointer($0) })
    var callbackStruct = AURenderCallbackStruct(inputProc: graphRenderProc,
                                                inputProcRefCon: referencePtr)
    
    CheckError(AudioUnitSetProperty(player.outputUnit!,
                         kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Global,
                         0,
                         &callbackStruct,
                         UInt32(MemoryLayout.size(ofValue: callbackStruct))), "Couldn't set render callback on output unit")
#endif
    
    // now initialize the graph (causes resources to be allocated)
    CheckError(AUGraphInitialize(audioGraph), "AUGraphInitialize failed")
    
    player.firstOutputSampleTime = -1
    
    debugPrint("Bottom of CreateMyAUGraph")
}

#if PART_II
func PrepareSpeechAU(_ player: inout MyAUGraphPlayer) -> Void
{
    var chan: SpeechChannel?
    var propsize: UInt32 = UInt32(MemoryLayout<SpeechChannel>.size)
    
    guard let speechUnit = player.speechUnit else {
        debugPrint("There is no speech unit before preparation")
        exit(-1)
    }
    
    CheckError(AudioUnitGetProperty(speechUnit,
                         kAudioUnitProperty_SpeechChannel,
                         kAudioUnitScope_Global,
                         0,
                         &chan,
                         &propsize), "AudioFileGetProperty[kAudioUnitProperty_SpeechChannel] failed")
    
    if let chan = chan {
        let cfstring = "Learning Core Audio is not an easy job but keep reading any thing about Core Audio. In the end, you will get a full map of the all stuff about Core Audio API" as CFString
        SpeakCFString(chan, cfstring, nil)
    }
}
#endif

// MARK: - Main
var player: MyAUGraphPlayer = MyAUGraphPlayer()

// Create the input unit
CreateInputUnit(&player)

// Build a graph with output unit
CreateMyAUGraph(&player)

#if PART_II
// Configure the speech synthesizer
PrepareSpeechAU(&player)
#endif

// Start playing
CheckError(AudioOutputUnitStart(player.inputUnit!), "AudioOutputUnitStart failed")
CheckError(AUGraphStart(player.graph!), "AUGraphStart failed")

// Wait
print("Capturing, presss <return> to stop")
getchar()

// clean up
AUGraphStop(player.graph!)
AUGraphUninitialize(player.graph!)
AUGraphClose(player.graph!)

