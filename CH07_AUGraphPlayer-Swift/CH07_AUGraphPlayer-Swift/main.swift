//
//  main.swift
//  CH07_AUGraphPlayer-Swift
//
//  Created by LEE CHIEN-MING on 11/04/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import AudioToolbox
import AudioUnit

private let kInputFileLocation: String = "/Users/derekli/Music/exercise.mp3"

struct MyAUGraphPlayer
{
    var inputFormat: AudioStreamBasicDescription?
    var inputFile: AudioFileID?
    
    var graph: AUGraph?
    var fileAU: AudioUnit?
}

func CreateMyAUGraph(with player: inout MyAUGraphPlayer) -> Void
{
    // Create a new AUGraph
    CheckError(NewAUGraph(&player.graph), "NewAUGraph failed")
    
    guard let graph = player.graph else {
        debugPrint("There is no AUGraph instance created!")
        return
    }
    // generate description tht will match out output device (speakers)
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
                   &outputNode),
               "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed")
    
    // generate description that will match a generator AU of type: audio file player
    var fileplayercd: AudioComponentDescription =
    AudioComponentDescription(componentType: kAudioUnitType_Generator,
                              componentSubType: kAudioUnitSubType_AudioFilePlayer,
                              componentManufacturer: kAudioUnitManufacturer_Apple,
                              componentFlags: 0,
                              componentFlagsMask: 0)
    
    // adds a node with above description to the graph
    var fileNode: AUNode = 0
    CheckError(AUGraphAddNode(graph,
                   &fileplayercd,
                   &fileNode),
               "AUGraphAddNode[kAudioUnitSubType_AudioFilePlayer] failed")
    
    // opening the graph opens all contained audio units but does not allocate any resources yet
    CheckError(AUGraphOpen(graph), "AUGraphOpen failed")
    
    // get the reference to the AudioUnit object for the file player graph node
    CheckError(AUGraphNodeInfo(graph,
                    fileNode,
                    nil,
                    &player.fileAU), "AUGraphNodeInfo failed")
    
    // connect the output source of the file player AU to the input source of the output node
    CheckError(AUGraphConnectNodeInput(graph,
                            fileNode,
                            0,
                            outputNode,
                            0), "AUGraphConnectNodeInput")
    
    // now initialize the graph (causes resources to be allocated)
    CheckError(AUGraphInitialize(graph), "AUGraphInitialize failed")
    
}

func makeScheduledAudioFileRegion() -> ScheduledAudioFileRegion {
    let tmp = UnsafeMutablePointer<ScheduledAudioFileRegion>.allocate(capacity: 1)
    memset(tmp, 0, MemoryLayout<ScheduledAudioFileRegion>.size)
    return tmp.move()
}

func PrepareFileAU(with player: inout MyAUGraphPlayer) -> Double
{
    // tell the file player unit to load the file we want to play
    guard let fileAU = player.fileAU else {
        debugPrint("There is no file AudioUnit before playing")
        return 0
    }
    
    CheckError(AudioUnitSetProperty(fileAU,
                         kAudioUnitProperty_ScheduledFileIDs,
                         kAudioUnitScope_Global,
                         0,
                         &player.inputFile,
                         UInt32(MemoryLayout<AudioFileID>.size)),
               "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFileIDs] failed")
    
    guard let inputFileID = player.inputFile else {
        debugPrint("There is no input file ID before playing")
        return 0
    }
    
    var nPackets: UInt64 = 0
    var propsize: UInt32 = UInt32(MemoryLayout.size(ofValue: nPackets))
    CheckError(AudioFileGetProperty(inputFileID,
                         kAudioFilePropertyAudioDataPacketCount,
                         &propsize,
                         &nPackets),
               "AudioFileGetProperty[kAudioFilePropertyAudioDataPacketCount] failed")
    
    // tell the file palyer AU to play the entire file
    var rgn: ScheduledAudioFileRegion = makeScheduledAudioFileRegion()
    rgn.mTimeStamp = AudioTimeStamp()
    rgn.mTimeStamp.mFlags = AudioTimeStampFlags.sampleTimeValid
    rgn.mTimeStamp.mSampleTime = 0
    rgn.mCompletionProc = nil
    rgn.mCompletionProcUserData = nil
    rgn.mAudioFile = inputFileID
    rgn.mLoopCount = 1
    rgn.mStartFrame = 0
    rgn.mFramesToPlay = UInt32(nPackets) * (player.inputFormat?.mFramesPerPacket)!
    
    CheckError(AudioUnitSetProperty(fileAU,
                         kAudioUnitProperty_ScheduledFileRegion,
                         kAudioUnitScope_Global,
                         0,
                         &rgn,
                         UInt32(MemoryLayout<ScheduledAudioFileRegion>.size)),
               "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFileRegion] failed")
    
    // prime the file palyer AU with default values
    var defaultValue: UInt32 = 0
    CheckError(AudioUnitSetProperty(fileAU,
                         kAudioUnitProperty_ScheduledFilePrime,
                         kAudioUnitScope_Global,
                         0,
                         &defaultValue,
                         UInt32(MemoryLayout<UInt32>.size)),
               "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFilePrime] failed")
    
    var startTime: AudioTimeStamp = AudioTimeStamp()
    startTime.mFlags = AudioTimeStampFlags.sampleTimeValid
    startTime.mSampleTime = -1
    CheckError(AudioUnitSetProperty(fileAU,
                         kAudioUnitProperty_ScheduleStartTimeStamp,
                         kAudioUnitScope_Global,
                         0,
                         &startTime,
                         UInt32(MemoryLayout<AudioTimeStamp>.size)),
               "AudioUnitSetProperty[kAudioUnitProperty_ScheduleStartTimeStamp]")
    
    // return file duration
    let frameCount = UInt32(nPackets) * (player.inputFormat?.mFramesPerPacket)!
    return Float64(frameCount) / (player.inputFormat?.mSampleRate)!
}

//=============================================================================
// Preparing to play auido file

let inputFileURL = URL(fileURLWithPath: kInputFileLocation)
var player: MyAUGraphPlayer = MyAUGraphPlayer()

// open the input audio file
CheckError(AudioFileOpenURL((inputFileURL as CFURL),
                 AudioFilePermissions.readPermission,
                 0,
                 &player.inputFile),
           "AudioFileOpenURL failed")

// get the audio data format from the file
var input_format: AudioStreamBasicDescription = AudioStreamBasicDescription()
var propsize: UInt32 = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
CheckError(AudioFileGetProperty(player.inputFile!,
                     kAudioFilePropertyDataFormat,
                     &propsize,
                     &input_format),
           "couldn't get file's data format")
player.inputFormat = input_format

// build a basic fileplayer->speakrs graph
CreateMyAUGraph(with: &player)

// configure the file player
let fileDuration = PrepareFileAU(with: &player)

guard let graph = player.graph else {
    exit(1)
}

// start playing
CheckError(AUGraphStart(graph), "AUGraphStart failed")

// sleep until the file is finished
usleep(UInt32(fileDuration * 1000.0 * 1000.0))

// clean up
AUGraphStop(graph)
AUGraphUninitialize(graph)
AUGraphClose(graph)
AudioFileClose(player.inputFile!)

debugPrint("Complete auido file playing")
