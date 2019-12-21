//
//  main.swift
//  CH05_Player-Swift
//
//  Created by LEE CHIEN-MING on 27/06/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import AudioToolbox

private let kPlaybackFileLocation = "/Users/derekli/bitbucket/shape_of_you.mp3"

private let kNumberPlaybackBuffers = 3

class MyPlayer {
    var playbackFile: AudioFileID?
    var packetPosition: Int64 = 0
    var numPacketsToRead: UInt32 = 0
    var packetDescs: UnsafeMutablePointer<AudioStreamPacketDescription>?
    var isDone = false
}

func CalculateBytesForTime(inAudioFile: AudioFileID, inDesc: AudioStreamBasicDescription, inSeconds: Float64, outBufferSize: inout UInt32, outNumPackets: inout UInt32) -> Void
{
    // first check to see what the max size of a packet is, if it is bigger than our default
    // allocation size, that needs to become larger
    var maxPacketSize: UInt32 = 0
    var propSize: UInt32 = UInt32(MemoryLayout.size(ofValue: maxPacketSize))
    CheckError(AudioFileGetProperty(inAudioFile,
                                    kAudioFilePropertyPacketSizeUpperBound,
                                    &propSize,
                                    &maxPacketSize), "couldn't get file's max packet size")
    
    let maxBufferSize: UInt32 = 0x10000 // limit size to 64k
    let minBufferSize: UInt32 = 0x4000 // limit size to 16k
    
    if (inDesc.mFramesPerPacket > 0) {
        let numPacketsForTime: Float64 = inDesc.mSampleRate / Float64(inDesc.mFramesPerPacket) * inSeconds
        outBufferSize = UInt32(numPacketsForTime) * maxPacketSize
    }
    else {
        // if frames per packet is zero, return a default buffer size
        outBufferSize = maxBufferSize > maxPacketSize ? maxBufferSize : maxPacketSize
    }
    
    // we are going to limit our size to our default
    if (outBufferSize > maxBufferSize && outBufferSize > maxPacketSize) {
        outBufferSize = maxBufferSize
    }
    else {
        // also make sure we're not too small - we don't want to go the disk for too small chunks
        if (outBufferSize < minBufferSize) {
            outBufferSize = minBufferSize
        }
    }
    
    outNumPackets = outBufferSize / maxPacketSize
}

func MyCopyEncoderCookieToQueue(theFile: AudioFileID, queue: AudioQueueRef)
{
    var propertySize: UInt32 = 0
    let result = AudioFileGetPropertyInfo(theFile,
                                          kAudioFilePropertyMagicCookieData,
                                          &propertySize,
                                          nil)
    
    if (result == noErr && propertySize > 0) {
        let alignment = MemoryLayout<UInt8>.alignment
        var magicCookie: UnsafeMutableRawPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(propertySize), alignment: alignment)
        CheckError(AudioFileGetProperty(theFile,
                             kAudioFilePropertyMagicCookieData,
                             &propertySize,
                             &magicCookie), "get cookie from file failed")
        CheckError(AudioQueueSetProperty(queue,
                              kAudioQueueProperty_MagicCookie,
                              magicCookie,
                              propertySize), "set cookie on queue failed")
        magicCookie.deallocate()
    }
}

let MyAQOutputCallback: AudioQueueOutputCallback = { (inUserData, inAQ, inCompleteAQBuffer) in

    let aqp_: MyPlayer? = inUserData?.bindMemory(to: MyPlayer.self, capacity: 1).pointee
    guard var aqp = aqp_ , let playbackFile = aqp.playbackFile else { return }
    if (true == aqp.isDone) { return }
    
    // read audio data from file into supplied buffer
    var numBytes: UInt32 = inCompleteAQBuffer.pointee.mAudioDataBytesCapacity // Set for input buffer size. This is required to prevent -50 error code
    
    var nPackets: UInt32 = aqp.numPacketsToRead
    CheckError(AudioFileReadPacketData(playbackFile,
                            false,
                            &numBytes,
                            aqp.packetDescs,
                            aqp.packetPosition,
                            &nPackets,
                            inCompleteAQBuffer.pointee.mAudioData), "AudioFileReadPackets failed")
    
    // enqueue buffer into the Audio Queue
    // if nPackets == 0 , it means we are EOF (all data has been read from file)
    if (nPackets > 0) {
        inCompleteAQBuffer.pointee.mAudioDataByteSize = numBytes
        CheckError(AudioQueueEnqueueBuffer(inAQ,
                                inCompleteAQBuffer,
                                (aqp.packetDescs != nil) ? nPackets : 0,
                                aqp.packetDescs), "AudioQueueEnqueueBuffer failed")

        aqp.packetPosition += Int64(nPackets)
        debugPrint("packetPosition: \(aqp.packetPosition)")
    }
    else {
        CheckError(AudioQueueStop(inAQ, false), "AudioQueueStop failed")
        aqp.isDone = true
    }
}


func main() -> Void
{
    var player = MyPlayer()

    let myFileURL = URL(fileURLWithPath: kPlaybackFileLocation)
    
    // open the audio file
    CheckError(AudioFileOpenURL(myFileURL as CFURL,
                     AudioFilePermissions.readPermission,
                     0,
                     &player.playbackFile), "AudioFileOpenURL failed")
    
    guard let playbackFile = player.playbackFile else { return }
    
    // get the audio data format from the file
    var dataFormat = AudioStreamBasicDescription()
    var propSize: UInt32 = UInt32(MemoryLayout.size(ofValue: dataFormat))
    CheckError(AudioFileGetProperty(playbackFile,
                         kAudioFilePropertyDataFormat,
                         &propSize,
                         &dataFormat), "couldn't get file's data format")
    
    // create a output (playback) queue
    var queueRef: AudioQueueRef?
    CheckError(AudioQueueNewOutput(&dataFormat,
                        MyAQOutputCallback,
                        &player, // user data
                        nil, // run loop
                        nil, // run loop mode
                        0, // flags (always 0)
                        &queueRef), // output: reference to AudioQueue object
                        "AudioQueueNewOutput failed")
    
    // adjust buffer size to represent about a half second
    var bufferByteSize: UInt32 = 0
    CalculateBytesForTime(inAudioFile: playbackFile,
                          inDesc: dataFormat,
                          inSeconds: 0.5,
                          outBufferSize: &bufferByteSize,
                          outNumPackets: &player.numPacketsToRead)
    
    // check if we are dealing with a VBR file. ASBD for VBR files always have 
    // mBytesPerPacket and mFramesPerPacket as 0 since they can fluctuate at any time
    // if we are dealing with VBR file, we allocate memory t ohold the packet descriptions
    let isFormatVBR = (dataFormat.mBytesPerPacket == 0 || dataFormat.mFramesPerPacket == 0)
    if (isFormatVBR) {
        let sizeOfASPD = MemoryLayout<AudioStreamPacketDescription>.size
        player.packetDescs = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: sizeOfASPD * Int(player.numPacketsToRead))
    }
    else {
        player.packetDescs = nil
    }
    
    guard let queue = queueRef else { return }
    // get magic cookie from file and set on queue
    MyCopyEncoderCookieToQueue(theFile: playbackFile, queue: queue)
    
    // allocate the buffers and prime the queue with some data before starting
    var buffers: [AudioQueueBufferRef?] = [AudioQueueBufferRef?](repeating: nil, count: 3)
    player.isDone = false
    player.packetPosition = 0
    
    withUnsafeMutablePointer(to: &player) {
        for idx in 0..<kNumberPlaybackBuffers {
            CheckError(AudioQueueAllocateBuffer(queue,
                                                bufferByteSize,
                                                &buffers[idx]), "AudioQueueAllocateBuffer failed")
            
            if let buffer = buffers[idx] {
                // Manually invoke callback to fill buffers with data
                MyAQOutputCallback($0, queue, buffer)
            }
            
            // EOF (the entire file's contents fit in the buffers)
            if ($0.pointee.isDone) { break }
        }
    }
    
    // start the queue. This function retruns immediately and begins
    CheckError(AudioQueueStart(queue, nil), "AudioQueueStart failed")
        
    // wait
    debugPrint("Playing...")
    repeat {
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.25, false)
    } while (player.isDone == false)
    
    // isDone represents the state of the Audio File enqueuing. This does not mean the 
    // Audio Queue is actually done playing yet. Since we have 3 half-second buffers in-flight
    // run for continue to run for a short addtional time so they can be processed
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 2, false)
    
    // end playback
    player.isDone = true
    CheckError(AudioQueueStop(queue, true), "AudioQueueStop failed")
    
    AudioQueueDispose(queue, true)
    AudioFileClose(playbackFile)
}

// Start to play music
main()

debugPrint("The playback process is done!")
