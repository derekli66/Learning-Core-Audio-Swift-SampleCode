//
//  main.swift
//  CH09_OpenALOrbitStream-Swift
//
//  Created by LEE CHIEN-MING on 22/11/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import AudioToolbox
import OpenAL

private let STREAM_PATH = "/Library/Audio/Apple Loops/Apple/iLife Sound Effects/Jingles/Kickflip Long.caf"
private let ORBIT_SPEED = 1
private let BUFFER_DURATION_SECONDS = 1.0
private let BUFFER_COUNT = 3
private let RUN_TIME = 20.0

class MyStreamPlayer
{
    var dataFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
    var bufferSizeBytes: UInt32 = 0
    var fileLengthFrames: Int64 = 0
    var totalFramesRead: Int64 = 0
    var sources: ALuint = 0
    var extAudioFile: ExtAudioFileRef?
}

func updateSourceLocation(_ player: MyStreamPlayer) -> Void
{
    let theta: Double = fmod(CFAbsoluteTimeGetCurrent() * ORBIT_SPEED.toDouble(), Double.pi * 2.0)
    print("Check theta: \(theta)")
    let x: ALfloat = ALfloat(3 * cos(theta))
    let y: ALfloat = ALfloat(0.5 * sin(theta))
    let z: ALfloat = ALfloat(1.0 * sin(theta))
    print("x=\(x), y=\(y), z=\(z)")
    alSource3f(player.sources, AL_POSITION, x, y, z)
}

func setUpExtAudioFile(_ player: MyStreamPlayer) -> OSStatus
{
    let streamFileURL = URL(fileURLWithPath: STREAM_PATH)
    
    player.dataFormat = AudioStreamBasicDescription(mSampleRate: 44100,
                                                    mFormatID: kAudioFormatLinearPCM,
                                                    mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                                    mBytesPerPacket: 2,
                                                    mFramesPerPacket: 1,
                                                    mBytesPerFrame: 2,
                                                    mChannelsPerFrame: 1,
                                                    mBitsPerChannel: 16,
                                                    mReserved: 0)
    CheckError(ExtAudioFileOpenURL((streamFileURL as CFURL), &player.extAudioFile),
               "Couldn't open ExtAudioFile for reading")
    
    // tell extAudioFile about our format
    CheckError(ExtAudioFileSetProperty(player.extAudioFile!,
                                       kExtAudioFileProperty_ClientDataFormat,
                                       sizeof(AudioStreamBasicDescription.self).toUInt32(),
                                       &player.dataFormat),
               "Couldn't set client format on ExtAudioFile")
    
    // figure out how big file is
    var propSize: UInt32 = sizeof(player.fileLengthFrames).toUInt32()
    ExtAudioFileGetProperty(player.extAudioFile!,
                            kExtAudioFileProperty_FileLengthFrames,
                            &propSize,
                            &player.fileLengthFrames)
    
    print("fileLengthFrames = \(player.fileLengthFrames) frames")
    
    player.bufferSizeBytes = (BUFFER_DURATION_SECONDS *
                              player.dataFormat.mSampleRate *
                              player.dataFormat.mBytesPerFrame.toDouble()).toUInt32()
    
    print("bufferSizeBytes = \(player.bufferSizeBytes)")
    
    print("Bottom of setUpExtAudioFile")
    
    return noErr
}

func fillALBuffer(_ player: MyStreamPlayer, _ alBuffer: ALuint) -> Void
{
    var bufferList: UnsafeMutableAudioBufferListPointer = AudioBufferList.allocate(maximumBuffers: 1)
    defer { free(bufferList.unsafeMutablePointer) }
    
    var sampleBuffer = UnsafeMutablePointer<UInt16>.allocate(capacity: player.bufferSizeBytes.toInt())
    defer { free(sampleBuffer) }
    
    bufferList[0].mNumberChannels = 1
    bufferList[0].mDataByteSize = player.bufferSizeBytes
    bufferList[0].mData = UnsafeMutableRawPointer(sampleBuffer)
    print("allocated \(player.bufferSizeBytes) byte buffer for ABL")
    
    // read from ExtAudioFile into sampleBuffer
    // TODO: handle end-of-file wraparound
    
    var framesReadIntoBuffer: UInt32 = 0
    repeat {
        var framesRead: UInt32 = player.fileLengthFrames.toUInt32() - framesReadIntoBuffer
        bufferList[0].mData = UnsafeMutableRawPointer(sampleBuffer + (framesReadIntoBuffer * sizeof(UInt16.self).toUInt32()).toInt())
        CheckError(ExtAudioFileRead(player.extAudioFile!,
                         &framesRead,
                         bufferList.unsafeMutablePointer), "ExtAudioFileRead failed")
        framesReadIntoBuffer += framesRead
        player.totalFramesRead += Int64(framesRead)
        print("read \(framesRead) frames")
    } while (framesReadIntoBuffer < player.bufferSizeBytes / sizeof(UInt16.self).toUInt32())
    
    // copy from sampleBuffer to AL buffer
    alBufferData(alBuffer,
                 AL_FORMAT_MONO16,
                 sampleBuffer,
                 ALsizei(player.bufferSizeBytes),
                 ALsizei(player.dataFormat.mSampleRate))
}

func refillALBuffers(_ player: MyStreamPlayer) -> Void
{
    var processed: ALint = 0
    alGetSourcei(player.sources, AL_BUFFERS_PROCESSED, &processed)
    CheckALError("Couldn't get al_buffers_processed")
    
    while (processed > 0) {
        var freeBuffer: ALuint = 0
        alSourceUnqueueBuffers(player.sources,
                               1,
                               &freeBuffer)
        CheckALError("Couldn't  unqueue buffer")
        print("refilling buffer \(freeBuffer)")
        fillALBuffer(player, freeBuffer)
        alSourceQueueBuffers(player.sources, 1, &freeBuffer)
        CheckALError("Couldn't queue refilled buffer")
        print("re-queued buffer \(freeBuffer)")
        processed -= 1;
    }
}

typealias ALCdevice = OpaquePointer
typealias ALCcontext = OpaquePointer

func main()
{
    let player: MyStreamPlayer = MyStreamPlayer()
    
    // Prepare the ExtAudioFile for reading
    CheckError(setUpExtAudioFile(player), "Couldn't open ExtAudioFile")
    
    // set up OpenAL buffers
    let alDevice: ALCdevice = alcOpenDevice(nil)
    CheckALError("Couldn't open AL device")
    
    let alContext: ALCcontext = alcCreateContext(alDevice, nil)
    CheckALError("Couldn't open AL context")
    
    alcMakeContextCurrent(alContext)
    CheckALError("Couldn't  make AL context current")
    
    var buffers: Array<ALuint> = Array<ALuint>(repeating:0, count:BUFFER_COUNT)
    alGenBuffers(ALsizei(BUFFER_COUNT), &buffers)
    CheckALError("Couldn't generate buffers")
    
    for idx in 0..<BUFFER_COUNT {
        fillALBuffer(player, buffers[idx])
    }
    
    // set up streaming source
    alGenSources(1, &player.sources)
    CheckALError("Couldn't generate sources")
    alSourcef(player.sources, AL_GAIN, ALfloat(AL_MAX_GAIN))
    CheckALError("Couldn't set source gain")
    updateSourceLocation(player)
    CheckALError("Couldn't set initial source position")
    
    // queue up the buffers on the source
    alSourceQueueBuffers(player.sources, ALsizei(BUFFER_COUNT), &buffers)
    CheckALError("Couldn't queue buffers on source")
    
    // set up listener
    alListener3f(AL_POSITION, 0.0, 0.0, 0.0)
    CheckALError("Couldn't set listener position")
    
    // start playing
    alSourcePlayv(1, &player.sources)
    CheckALError("Couldn't play")
    
    // and wait
    print("Playing...")
    let startTime: time_t = time(nil)
    
    repeat {
        // get next theta
        updateSourceLocation(player)
        CheckALError("Couldn't set source position")
        
        // refill buffers if needed
        refillALBuffers(player)
        
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.1, false)
    } while(difftime(time(nil), startTime) < RUN_TIME)
    
    // cleanup
    alSourceStop(player.sources)
    alDeleteSources(1, &player.sources)
    alDeleteBuffers(ALsizei(BUFFER_COUNT), buffers)
    alcDestroyContext(alContext)
    alcCloseDevice(alDevice)
    print("Bottom of main")
}

main()
