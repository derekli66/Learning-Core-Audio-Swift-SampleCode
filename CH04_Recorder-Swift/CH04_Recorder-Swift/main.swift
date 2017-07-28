//
//  main.swift
//  CH04_Recorder-Swift
//
//  Created by LEE CHIEN-MING on 23/07/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import AudioToolbox

private let kNumberRecordBuffers = 3

class MyRecorder
{
    var recordFile: AudioFileID?
    var recordPacket: Int64 = 0
    var running: Bool = false
}

extension Int {
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

extension UInt32 {
    func toInt64() -> Int64 {
        return Int64(self)
    }
    func toInt() -> Int {
        return Int(self)
    }
}

extension Float {
    func toFloat64() -> Float64 {
        return Float64(self)
    }
}

extension Double {
    func toInt() -> Int {
        return Int(self)
    }
    
    func toUInt32() -> UInt32 {
        return UInt32(self)
    }
}

postfix operator ~>
extension UnsafePointer where Pointee == AudioStreamBasicDescription {
    static postfix func ~> (pointer: UnsafePointer<AudioStreamBasicDescription>) -> AudioStreamBasicDescription {
        return pointer.pointee
    }
}

extension UnsafeMutablePointer where Pointee == MyRecorder {
    static postfix func ~> (pointer: UnsafeMutablePointer<MyRecorder>) -> MyRecorder {
        return pointer.pointee
    }
}

extension UnsafeMutablePointer where Pointee == AudioQueueBuffer {
    static postfix func ~> (pointer: UnsafeMutablePointer<AudioQueueBuffer>) -> AudioQueueBuffer {
        return pointer.pointee
    }
}

// MARK: - Utility Functions

func MyGetDefaultInputDevicesSampleRate(_ outSampleRate: UnsafeMutablePointer<Float64>) -> OSStatus
{
    var error: OSStatus = noErr
    var deviceID: AudioDeviceID = 0
    
    // get the default input device
    var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: 0)
    var propertySize: UInt32 = MemoryLayout<AudioDeviceID>.size.toUInt32()
    error = AudioHardwareServiceGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &propertyAddress,
                                                0,
                                                nil,
                                                &propertySize,
                                                &deviceID)
    if (error != noErr) { return error }
    
    // get its sample rate
    propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
    propertyAddress.mElement = 0
    propertySize = MemoryLayout<Float64>.size.toUInt32()
    error = AudioHardwareServiceGetPropertyData(deviceID,
                                                &propertyAddress,
                                                0,
                                                nil,
                                                &propertySize,
                                                outSampleRate)
    
    return error
}

func MyComputeRecordBufferSize(_ format: UnsafePointer<AudioStreamBasicDescription>, _ queue: AudioQueueRef, _ seconds: Float) -> UInt32
{
    var packets: UInt32 = 0
    var frames: UInt32 = 0
    var bytes: UInt32 = 0
    
    frames = ceil(seconds.toFloat64() * format~>.mSampleRate).toUInt32()
    
    if (format~>.mBytesPerFrame > 0 ) {                     // 1
        bytes = frames * format~>.mBytesPerFrame
    }
    else {
        var maxPacketSize: UInt32 = 0
        if (format~>.mBytesPerPacket > 0) {                 // 2
            maxPacketSize = format.pointee.mBytesPerPacket
        }
        else {
            // get the largest single packet size possible
            var propertySize: UInt32 = MemoryLayout.size(ofValue: maxPacketSize).toUInt32()
            CheckError(AudioQueueGetProperty(queue,
                                  kAudioConverterPropertyMaximumOutputPacketSize,
                                  &maxPacketSize,
                                  &propertySize), "couldn't get queue's maximum output packet size")
        }
        
        if (format~>.mFramesPerPacket > 0) {
            packets = frames / format~>.mFramesPerPacket
        }
        else {
            // worst-case scenario: 1 frame in a packet. WHY?
            packets = frames
        }
        
        if (0 == packets) {  // sanitfy check
            packets = 1;
        }
        
        bytes = packets * maxPacketSize
    }
    
    return bytes;
}

// Copy a queue's encoder's magic cookie to an audio file
func MyCopyEncoderCookieToFile(_ queue: AudioQueueRef, _ theFile: AudioFileID) -> Void
{
    var propertySize: UInt32 = 0
    
    // get the magic cookie, if any, from the queue's converter
    let result: OSStatus = AudioQueueGetPropertySize(queue,
                                                     kAudioConverterCompressionMagicCookie,
                                                     &propertySize)
    if (noErr == result && propertySize > 0) {
        // there is valid cookie data to be fetched, get it.
        let magicCookie = UnsafeMutablePointer<UInt8>.allocate(capacity: propertySize.toInt())
        magicCookie.initialize(to: 0, count: propertySize.toInt())
        CheckError(AudioQueueGetProperty(queue,
                              kAudioQueueProperty_MagicCookie,
                              magicCookie,
                              &propertySize), "get audio queue's magic cookie")
        
        // now set the magic cookie on the output file
        CheckError(AudioFileSetProperty(theFile,
                             kAudioFilePropertyMagicCookieData,
                             propertySize,
                             magicCookie), "set audio file's magic cookie")
        magicCookie.deinitialize(count: propertySize.toInt())
        magicCookie.deallocate(capacity: propertySize.toInt())
    }
}

// MARK: - Audio Queue

// Audio Queue callback function, called when an input buffer has been filled
let MyAQInputCallback: AudioQueueInputCallback = {
(inUserData: UnsafeMutableRawPointer?,
    inAQ: AudioQueueRef,
    inBuffer: AudioQueueBufferRef,
    inStartTime: UnsafePointer<AudioTimeStamp>,
    inNumberPacketDescriptions: UInt32,
    inPacketDescs: UnsafePointer<AudioStreamPacketDescription>?) in
    
    var recorderRef = inUserData?.bindMemory(to: MyRecorder.self, capacity: 1)
    guard let recorder = recorderRef else { return }
    var inNumPackets = inNumberPacketDescriptions
    
    if (inNumPackets > 0) {
        //  write packets to file
        CheckError(AudioFileWritePackets(recorder~>.recordFile!,
                              false,
                              inBuffer~>.mAudioDataByteSize,
                              inPacketDescs,
                              recorder~>.recordPacket,
                              &inNumPackets,
                              inBuffer~>.mAudioData), "AudioFileWritePackets failed")
        
        // increment packet index
        recorder~>.recordPacket += inNumPackets.toInt64()
    }
    
    // if we're not stopping, re-enqueue the buffer so that it gets filled again
    if (recorder~>.running) {
        CheckError(AudioQueueEnqueueBuffer(inAQ,
                                inBuffer,
                                0,
                                nil), "AudioQueueEnqueueBuffer failed")
    }
}

func main() -> Void
{
    var recorder = MyRecorder()
    var recordFormat = AudioStreamBasicDescription()
    
    // Configure the output data format to be AAC
    recordFormat.mFormatID = kAudioFormatMPEG4AAC
    recordFormat.mChannelsPerFrame = 2
    
    // get the sample rate of the default input device
    // we use this to adapt the output data format to match hardware capabilities
    _ = MyGetDefaultInputDevicesSampleRate(&recordFormat.mSampleRate)
    
    // ProTip: Use the AudioFormat API to trivialize ASBD creation.
    //         input: at least the mFormatID, however, at this point we already have
    //                mSampleRate, mFormatID, and mChannelsPerFrame
    //         output: the remainder of the ASBD will be filled out as much as possible
    //                 given the information known about the format
    var propSize = MemoryLayout.size(ofValue: recordFormat).toUInt32()
    CheckError(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo,
                           0,
                           nil,
                           &propSize,
                           &recordFormat), "AudioFormatGetProperty failed")
    
    // create a input (recording) queue
    var queue_: AudioQueueRef?
    CheckError(AudioQueueNewInput(&recordFormat,
                       MyAQInputCallback,
                       &recorder,
                       nil,
                       nil,
                       0,
                       &queue_), "AudioQueueNewInput failed")
    
    guard let queue = queue_ else { exit(1) }
    
    // since the queue is now initilized, we ask it's Audio Converter object
    // for the ASBD it has configured itself with. The file may require a more
    // specific stream description than was necessary to create the audio queue.
    //
    // for example: certain fields in an ASBD cannot possibly be known until it's
    // codec is instantiated (in this case, by the AudioQueue's Audio Converter object)
    var size = MemoryLayout.size(ofValue: recordFormat).toUInt32()
    CheckError(AudioQueueGetProperty(queue,
                          kAudioConverterCurrentOutputStreamDescription,
                          &recordFormat,
                          &size), "couldn't get queue's format")
    
    let myFileURL = URL(fileURLWithPath: "output.caf")
    CheckError(AudioFileCreateWithURL(myFileURL as CFURL,
                           kAudioFileCAFType,
                           &recordFormat,
                           AudioFileFlags.eraseFile,
                           &recorder.recordFile), "AudioFileCreateWithURL failed")
    
    // many encoded formats require a 'magic cookie'. we set the cookie first
    // to give the file object as much info as we can about the data it will be receiving
    MyCopyEncoderCookieToFile(queue, recorder.recordFile!)
    
    // allocate and enqueue buffers
    let bufferBytesSize = MyComputeRecordBufferSize(&recordFormat, queue, 0.5)
    for _ in 0..<kNumberRecordBuffers {
        var buffer: AudioQueueBufferRef?
        CheckError(AudioQueueAllocateBuffer(queue,
                                 bufferBytesSize,
                                 &buffer), "AudioQueueAllocateBuffer failed")
        CheckError(AudioQueueEnqueueBuffer(queue,
                                buffer!,
                                0,
                                nil), "AudioQueueEnqueueBuffer failed")
    }
    
    // start the queue. this function return immedatly and begins
    // invoking the callback, as needed, asynchronously.
    recorder.running = true;
    CheckError(AudioQueueStart(queue, nil), "AudioQueueStart failed")
    
    // and wait
    debugPrint("Recording, press <return> to stop: ")
    getchar();
    
    // end recording
    debugPrint("* recording done *")
    recorder.running = false
    CheckError(AudioQueueStop(queue, true), "AudioQueueStop failed")
    
    // a codec may update its magic cookie at the end of an encoding session
    // so reapply it to the file now
    MyCopyEncoderCookieToFile(queue, recorder.recordFile!)
    
    AudioQueueDispose(queue, true)
    AudioFileClose(recorder.recordFile!)
}

main()




