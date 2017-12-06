//
//  main.swift
//  CH09_OpenALOrbitLoop-Swift
//
//  Created by LEE CHIEN-MING on 19/08/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import AudioToolbox
import OpenAL

private let LOOP_PATH = "/Library/Audio/Apple Loops/Apple/iLife Sound Effects/Transportation/Bicycle Coasting.caf"
private let ORBIT_SPEED = 1
private let RUN_TIME = 20.0

private extension Int {
    func toUInt32() -> UInt32 {
        return UInt32(self)
    }
    
    func toFloat64() -> Float64 {
        return Float64(self)
    }
    
    func toDouble() -> Double {
        return Double(self)
    }
}

private extension Int64 {
    func toUInt32() -> UInt32 {
        return UInt32(self)
    }
    
    func toFloat64() -> Float64 {
        return Float64(self)
    }
    
    func toDouble() -> Double {
        return Double(self)
    }
}

private extension UInt32 {
    func toInt() -> Int {
        return Int(self)
    }
}

class MyLoopPlayer {
    var dataFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
    var sampleBuffer: UnsafeMutablePointer<UInt16>?
    var bufferSizeBytes: UInt32 = 0
    var sources: ALuint = 0
}

func CheckALError(_ operation: String) -> Void
{
    let alErr = alGetError()
    if alErr == AL_NO_ERROR { return }
    var errFormat = ""
    switch alErr {
    case AL_INVALID_NAME:
        errFormat = "OpenAL Error: \(operation) (AL_INVALID_NAME)"
    case AL_INVALID_VALUE:
        errFormat = "OpenAL Error: \(operation) (AL_INVALID_VALUE)"
    case AL_INVALID_ENUM:
        errFormat = "OpenAL Error: \(operation) (AL_INVALID_ENUM)"
    case AL_INVALID_OPERATION:
        errFormat = "OpenAL Error: \(operation) (AL_INVALID_OPERATION)"
    case AL_OUT_OF_MEMORY:
        errFormat = "OpenAL Error: \(operation) (AL_OUT_OF_MEMORY)"
    default:
        break
    }
    
    debugPrint(errFormat)
    exit(1)
}

private func sizeof<T>(_ instance: T) -> Int
{
    return MemoryLayout.size(ofValue: instance)
}

private func sizeof<T>(_ type: T.Type) -> Int
{
    return MemoryLayout<T>.size
}

func updateSourceLocation(_ player: MyLoopPlayer) -> Void
{
    let theta: Double = fmod( CFAbsoluteTimeGetCurrent() * ORBIT_SPEED.toDouble() , Double.pi * 2.0)
    let x: ALfloat =  ALfloat( 3 * cos(theta))
    let y: ALfloat = ALfloat(0.5 * sin(theta))
    let z: ALfloat = ALfloat(1.0 * sin(theta))
    debugPrint("x=\(x), y=\(y), z=\(z)")
    alSource3f(player.sources, AL_POSITION, x, y, z)
}

func loadLoopIntoBuffer(_ player: MyLoopPlayer) -> OSStatus
{
    let loopFileURL = URL(fileURLWithPath: LOOP_PATH)
    
    // describe the client format - AL needs mono
    player.dataFormat = AudioStreamBasicDescription(mSampleRate: 44100.0,
                                                    mFormatID: kAudioFormatLinearPCM,
                                                    mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                                    mBytesPerPacket: 2,
                                                    mFramesPerPacket: 1,
                                                    mBytesPerFrame: 2,
                                                    mChannelsPerFrame: 1,
                                                    mBitsPerChannel: 16,
                                                    mReserved: 0)
    
    var extAudioFile: ExtAudioFileRef?
    CheckError(ExtAudioFileOpenURL(loopFileURL as CFURL, &extAudioFile),
               "Couldn't open ExtAudioFile for reading")
    
    guard let extAudioFileUnwrapped = extAudioFile else {
        return kAudioFileFileNotFoundError
    }
    
    // tell extAudioFile about our format
    CheckError(ExtAudioFileSetProperty(extAudioFileUnwrapped,
                            kExtAudioFileProperty_ClientDataFormat,
                            sizeof(AudioStreamBasicDescription.self).toUInt32(),
                            &player.dataFormat), "Couldn't set client format on ExtAudioFile")
    
    // figure out how big a buffer we need
    var fileLengthFrames: Int64 = 0
    var propSize: UInt32 = sizeof(fileLengthFrames).toUInt32()
    CheckError(ExtAudioFileGetProperty(extAudioFileUnwrapped,
                            kExtAudioFileProperty_FileLengthFrames,
                            &propSize,
                            &fileLengthFrames), "Couldn't get file length frames from ExtAudioFile")
    
    debugPrint("plan on reading \(fileLengthFrames) frames")
    player.bufferSizeBytes = fileLengthFrames.toUInt32() * player.dataFormat.mBytesPerFrame
    
    let buffersRef: UnsafeMutableAudioBufferListPointer = AudioBufferList.allocate(maximumBuffers: 1)
    
    // allocate sample buffer
    player.sampleBuffer = UnsafeMutablePointer<UInt16>.allocate(capacity: player.bufferSizeBytes.toInt())
    
    buffersRef[0].mNumberChannels = 1
    buffersRef[0].mDataByteSize = player.bufferSizeBytes
    buffersRef[0].mData = UnsafeMutableRawPointer(player.sampleBuffer)
    
    debugPrint("Created AudioBufferList")
    
    // loop reading into the ABL until buffer is full
    var totalFramesRead: UInt32 = 0
    repeat {
        var framesRead: UInt32 = fileLengthFrames.toUInt32() - totalFramesRead;
        guard let sampleBuffer = player.sampleBuffer else { break }
        buffersRef[0].mData = UnsafeMutableRawPointer(sampleBuffer + Int(totalFramesRead * sizeof(UInt16.self).toUInt32()))
        CheckError(ExtAudioFileRead(extAudioFileUnwrapped,
                         &framesRead,
                         buffersRef.unsafeMutablePointer), "ExtAudioFileRead failed")
        totalFramesRead += framesRead
        debugPrint("Read \(framesRead) frames")
    } while (totalFramesRead < fileLengthFrames.toUInt32())
    
    free(buffersRef.unsafeMutablePointer)
    return noErr
}

typealias ALCdevice = OpaquePointer
typealias ALCcontext = OpaquePointer

func main()
{
    let player: MyLoopPlayer = MyLoopPlayer()
    
    // convert to an OpenAL-friendly format and read into memory
    CheckError(loadLoopIntoBuffer(player), "Couldn't load loop into buffer")
    
    // set up OpenAL buffer
    let alDevice: ALCdevice = alcOpenDevice(nil)
    CheckALError("Couldn't open AL device")
    let alContext: ALCcontext = alcCreateContext(alDevice, nil)
    CheckALError("Couldn't open AL context")
    alcMakeContextCurrent(alContext)
    CheckALError("Couldn't make AL context current")
    var buffers: Array<ALuint> = [ALuint(0)]
//    var buffers: ALuint = ALuint(0)
    alGenBuffers(1, &buffers)
    CheckALError("Couldn't generate buffers")
    alBufferData(buffers[0],
                 AL_FORMAT_MONO16,
                 player.sampleBuffer,
                 ALsizei(player.bufferSizeBytes),
                 ALsizei(player.dataFormat.mSampleRate))
    
    // AL copies the samples, so we can free them now
    free(player.sampleBuffer)
    
    // set up OpenAL source
    alGenSources(1, &player.sources)
    CheckALError("Couldn't generate sources");
    alSourcei(player.sources, AL_LOOPING, AL_TRUE)
    CheckALError("Couldn't set source looping property")
    alSourcef(player.sources, AL_GAIN, ALfloat(AL_MAX_GAIN))
    CheckALError("Couldn't set source again")
    updateSourceLocation(player)
    CheckALError("Couldn't set initial source position")
    
    // connect buffer to source
    alSourcei(player.sources, AL_BUFFER, ALint(buffers[0]))
    CheckALError("Couldn't connect buffer to source")
    
    // set up listener
    alListener3f(AL_POSITION, 0.0, 0.0, 0.0)
    
    // start playing
    alSourcePlay(player.sources)
    
    // and wait
    print("Playing...")
    let startTime: time_t = time(nil)
    
    repeat {
        // get next theta
        updateSourceLocation(player)
        CheckALError("Couldn't set looping source position")
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.1, false)
    } while (difftime(time(nil), startTime) < RUN_TIME)
    
    // cleanup:
    alSourceStop(player.sources)
    alDeleteSources(1, &player.sources)
    alDeleteBuffers(1, &buffers)
    alcDestroyContext(alContext)
    alcCloseDevice(alDevice)
    print("Bottom of main")
}

main()

