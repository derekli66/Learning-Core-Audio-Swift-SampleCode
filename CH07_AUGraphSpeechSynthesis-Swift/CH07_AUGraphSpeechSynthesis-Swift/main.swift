//
//  main.swift
//  CH07_AUGraphSpeechSynthesis-Swift
//
//  Created by LEE CHIEN-MING on 13/04/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import AudioToolbox
import AudioUnit
import ApplicationServices

struct MyAUGraphPlayer
{
    var streamFormat: AudioStreamBasicDescription?
    
    var graph: AUGraph?
    var speechAU: AudioUnit?
    var reverbAU: AudioUnit?
    var outputAU: AudioUnit?
}

let ReverbPullingRenderProc: AURenderCallback = {
    (inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?) in
    
    let player = inRefCon.bindMemory(to: MyAUGraphPlayer.self, capacity: 1).pointee
    
    guard let reverbAU = player.reverbAU, let ioData = ioData else {
        return kAudioUnitErr_InvalidElement
    }
    
    AudioUnitRender(reverbAU,
                    ioActionFlags,
                    inTimeStamp,
                    0,
                    inNumberFrames,
                    ioData)
    
    return noErr
}

func CreateMyAUGraph(_ player: inout MyAUGraphPlayer) -> Void
{
    // create a new AUGraph
    CheckError(NewAUGraph(&player.graph),
               "NewAUGraph failed")
    
    guard let graph = player.graph else {
        debugPrint("There is no graph for further processing")
        return
    }
    
    // generate description tht will match our output device (speakers)
    var outputcd: AudioComponentDescription =
        AudioComponentDescription(componentType: kAudioUnitType_Output,
                                  componentSubType: kAudioUnitSubType_DefaultOutput,
                                  componentManufacturer: kAudioUnitManufacturer_Apple,
                                  componentFlags: 0,
                                  componentFlagsMask: 0)
    
    // adds a node with above description to the graph
    var outputNode: AUNode = 0
    CheckError(AUGraphAddNode(graph,
                   &outputcd,
                   &outputNode), "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed")
    
    // generate description that will match a generator AU of type: speech synthesizer
    var speechcd: AudioComponentDescription =
        AudioComponentDescription(componentType: kAudioUnitType_Generator,
                                  componentSubType: kAudioUnitSubType_SpeechSynthesis,
                                  componentManufacturer: kAudioUnitManufacturer_Apple,
                                  componentFlags: 0,
                                  componentFlagsMask: 0)
    
    // adds a node with above description to the graph
    var speechNode: AUNode = 0
    CheckError(AUGraphAddNode(graph,
                   &speechcd,
                   &speechNode), "AUGraphAddNode[kAudioUnitSubType_SpeechSynthesis] failed")
    
    // opening the graph opens all contained audio units but does not allocate any resources yet
    CheckError(AUGraphOpen(graph), "AUGraphOpen failed")
    
    // get the reference to the AudioUnit object for the speech synthesis graph node
    CheckError(AUGraphNodeInfo(graph,
                    speechNode,
                    nil,
                    &player.speechAU), "AUGraphNodeInfo failed")
    
#if PART_II
    //
    // FUN! re-route the speech thru a reverb effect before sending to speakers
    //
    // generate description that will match out reverb effect
    var reverbcd: AudioComponentDescription =
        AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                  componentSubType: kAudioUnitSubType_MatrixReverb,
                                  componentManufacturer: kAudioUnitManufacturer_Apple,
                                  componentFlags: 0,
                                  componentFlagsMask: 0)
    
    // adds a node with above description to the graph
    var reverbNode: AUNode = 0
    CheckError(AUGraphAddNode(graph,
                   &reverbcd,
                   &reverbNode), "AUGraphAddNode[kAudioUnitSubType_MatrixReverb] failed")
    
    // connect the output source of the speech synthesizer AU to the input source of the reverb node
    CheckError(AUGraphConnectNodeInput(graph,
                            speechNode,
                            0,
                            reverbNode,
                            0), "AUGraphConnectNodeInput")
    
    // connect the output source of the reverb AU to the input source of the output node
//    CheckError(AUGraphConnectNodeInput(graph,
//                            reverbNode,
//                            0,
//                            outputNode,
//                            0), "AUGraphConnectNodeInput")
    
    // get the reference to the AudioUnit object for the reverb graph node
    var reverbAudioUnit: AudioUnit?
    CheckError(AUGraphNodeInfo(graph,
                    reverbNode,
                    nil,
                    &reverbAudioUnit), "AUGraphNodeInfo failed")
    
    guard let reverbUnit = reverbAudioUnit else {
        debugPrint("Cannot get the reverb unit")
        return
    }
    
    //---------------------------------------------------------------------
    // Start to set up render callback on output unit
    // Get ASBD from reverb unit and then set it to output unit
    
    player.reverbAU = reverbUnit
    
    var outASBD = AudioStreamBasicDescription()
    var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    CheckError(AudioUnitGetProperty(reverbUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Output,
                         0,
                         &outASBD,
                         &propertySize), "Couldn't get ASBD from reverb unit")
    
    CheckError(AUGraphNodeInfo(graph, outputNode, nil, &player.outputAU), "Couldn't get output unit")
    
    guard let outputAU = player.outputAU else {
        debugPrint("Cannot get the output unit")
        return
    }
    
    propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    CheckError(AudioUnitSetProperty(outputAU,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         0,
                         &outASBD,
                         propertySize), "Couldn't set ASBD on output unit's input scope")
    
    var renderCallbackStruct = AURenderCallbackStruct(inputProc: ReverbPullingRenderProc,
                                                      inputProcRefCon: UnsafeMutableRawPointer(&player))
    
    CheckError(AudioUnitSetProperty(outputAU,
                         kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Global,
                         0,
                         &renderCallbackStruct,
                         UInt32(MemoryLayout.size(ofValue: renderCallbackStruct))), "Couldn't set render callback on output unit")
    
    //---------------------------------------------------------------------
    
    /*
     enum {
     kReverbRoomType_SmallRoom		= 0,
     kReverbRoomType_MediumRoom		= 1,
     kReverbRoomType_LargeRoom		= 2,
     kReverbRoomType_MediumHall		= 3,
     kReverbRoomType_LargeHall		= 4,
     kReverbRoomType_Plate			= 5,
     kReverbRoomType_MediumChamber	= 6,
     kReverbRoomType_LargeChamber	= 7,
     kReverbRoomType_Cathedral		= 8,
     kReverbRoomType_LargeRoom2		= 9,
     kReverbRoomType_MediumHall2		= 10,
     kReverbRoomType_MediumHall3		= 11,
     kReverbRoomType_LargeHall2		= 12
     };
     */
    
    // now initialize the graph (causes resources to be allocated)
    CheckError(AUGraphInitialize(graph), "AUGraphInitialize failed")
    
    // set the reverb preset for room size
    // var roomType: UInt32 = AUReverbRoomType.reverbRoomType_SmallRoom.rawValue
    // var roomType: UInt32 = AUReverbRoomType.reverbRoomType_MediumRoom.rawValue
     var roomType: UInt32 = AUReverbRoomType.reverbRoomType_LargeHall.rawValue
    // var roomType: UInt32 = AUReverbRoomType.reverbRoomType_Cathedral.rawValue
    
    CheckError(AudioUnitSetProperty(reverbUnit,
                         kAudioUnitProperty_ReverbRoomType,
                         kAudioUnitScope_Global,
                         0,
                         &roomType,
                         UInt32(MemoryLayout<UInt32>.size)),
               "AudioUnitSetProperty[kAudioUnitProperty_ReverbRoomType] failed")
#else
    // connect the output source of the speech synthesis AU to the input source of the output node
    CheckError(AUGraphConnectNodeInput(graph, speechNode, 0, outputNode, 0),
               "AUGraphConnectNodeInput")
    
    CheckError(AUGraphInitialize(graph), "AUGraphInitialize failed")
#endif
    
    CAShow(UnsafeMutablePointer<AUGraph>(graph))
}

func PrepareSpeechAU(_ player: inout MyAUGraphPlayer) -> Void
{
    var chan: SpeechChannel?
    var propsize: UInt32 = UInt32(MemoryLayout<SpeechChannel>.size)
    
    CheckError(AudioUnitGetProperty(player.speechAU!,
                         kAudioUnitProperty_SpeechChannel,
                         kAudioUnitScope_Global,
                         0,
                         &chan,
                         &propsize),
               "AudioUnitGetProperty[kAudioUnitProperty_SpeechChannel] failed")
    
    guard let speChan = chan else {
        debugPrint("Cannot get SpeechChannel after get property from speech AU")
        exit(1)
    }
    
    SpeakCFString(speChan, "hello world. I am using a speech synthesis" as CFString, nil)
}

// MARK: main

var speechPlayer: MyAUGraphPlayer = MyAUGraphPlayer()

// build a basic speech->speakers graph
CreateMyAUGraph(&speechPlayer)

// configure the speech synthesizer
PrepareSpeechAU(&speechPlayer)

guard let graph = speechPlayer.graph else {
    debugPrint("There is no AUGraph for start")
    exit(1)
}

// start playing
CheckError(AUGraphStart(graph), "AUGraphStart failed")

usleep(UInt32(10 * 1000.0 * 1000.0 ))

// clean up
AUGraphStop(graph)
AUGraphUninitialize(graph)
AUGraphClose(graph)
DisposeAUGraph(graph)
