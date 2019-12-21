//
//  main.swift
//  CH06_AudioConverter-Swift
//
//  Created by LEE CHIEN-MING on 14/06/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import AudioToolbox

private let kInputFileLocation = "/Users/derekli/bitbucket/shape_of_you.mp3"

struct MyAudioConverterSettings
{
    var inputFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
    var outputFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
    
    var inputFile: AudioFileID?
    var outputFile: AudioFileID?
    
    var inputFilePacketIndex: UInt64 = 0
    var inputFilePacketCount: UInt64 = 0
    var inputFilePacketMaxSize: UInt32 = 0
    
    var inputFilePacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
    var sourceBuffer: UnsafeMutableRawPointer?
}

let myAudioConverterCallback: AudioConverterComplexInputDataProc = {
    (inAudioConverter: AudioConverterRef,
     ioDataPacketCount: UnsafeMutablePointer<UInt32>,
     ioData: UnsafeMutablePointer<AudioBufferList>,
     outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
     inUserData: UnsafeMutableRawPointer?) in
    
    let audioConverterSettingsRef = inUserData?.bindMemory(to: MyAudioConverterSettings.self, capacity: 1)
    
    // initialize in case of failure
    let audioBufferListRef = UnsafeMutableAudioBufferListPointer(ioData)
    audioBufferListRef[0].mData = nil
    audioBufferListRef[0].mDataByteSize = 0
    
    guard var audioConverterSettings = audioConverterSettingsRef?.pointee else {
        return kAudioConverterErr_UnspecifiedError
    }
    
    // if there are not enough packets to satisfy request, then read what's left
    if (audioConverterSettings.inputFilePacketIndex + UInt64(ioDataPacketCount.pointee) > audioConverterSettings.inputFilePacketCount) {
        ioDataPacketCount.pointee = UInt32(audioConverterSettings.inputFilePacketCount - audioConverterSettings.inputFilePacketIndex)
    }
    
    if (ioDataPacketCount.pointee == 0) { return noErr }
    
    if (audioConverterSettings.sourceBuffer != nil) {
        free(audioConverterSettings.sourceBuffer!)
        audioConverterSettings.sourceBuffer = nil
    }
    
    audioConverterSettings.sourceBuffer = calloc(1, Int(ioDataPacketCount.pointee * UInt32((audioConverterSettingsRef?.pointee.inputFilePacketMaxSize)!)))
    
    var outByteCount: UInt32 = 0
    var result = AudioFileReadPacketData(audioConverterSettings.inputFile!,
                                         true,
                                         &outByteCount,
                                         audioConverterSettings.inputFilePacketDescriptions,
                                         Int64(audioConverterSettings.inputFilePacketIndex),
                                         ioDataPacketCount,
                                         audioConverterSettings.sourceBuffer)

    if (result == kAudioFileEndOfFileError && ioDataPacketCount.pointee > 0) {
        result = noErr
    }
    else if (result != noErr) {
        return result
    }
    
    audioConverterSettings.inputFilePacketIndex += UInt64(ioDataPacketCount.pointee)
    
    audioBufferListRef[0].mData = audioConverterSettings.sourceBuffer
    audioBufferListRef[0].mDataByteSize = outByteCount
    
    if (outDataPacketDescription != nil) {
        outDataPacketDescription?.pointee = audioConverterSettings.inputFilePacketDescriptions
    }

    return result
}

func Convert(_ mySettings: inout MyAudioConverterSettings)
{
    // create audioConverter object
    var audioConverterRef: AudioConverterRef?
    CheckError(AudioConverterNew(&mySettings.inputFormat,
                      &mySettings.outputFormat,
                      &audioConverterRef), "AudioConverterNew failed")
    
    guard let audioConverter = audioConverterRef else {
        debugPrint("Couldn't unwrap audioConveterRef")
        exit(-1)
    }
    
    // allocate packet descriptions if the input file is VBR
    var packetsPerBuffer: UInt32 = 0
    var outputBufferSize: UInt32 = 32 * 1024 // 32KB is a good starting point
    var sizePerPacket = mySettings.inputFormat.mBytesPerPacket
    if (0 == sizePerPacket) {
        var size: UInt32 = UInt32(MemoryLayout.size(ofValue: sizePerPacket))
        CheckError(AudioConverterGetProperty(audioConverter,
                                  kAudioConverterPropertyMaximumOutputPacketSize,
                                  &size,
                                  &sizePerPacket), "Couldn't get kAudioConverterPropertyMaximumOutputPacketSize")
        // make sure the buffer is large enough ot hold at least one packet
        if (sizePerPacket > outputBufferSize) {
            outputBufferSize = sizePerPacket
        }
        
        packetsPerBuffer = outputBufferSize / sizePerPacket
        mySettings.inputFilePacketDescriptions = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: MemoryLayout<AudioStreamPacketDescription>.size * Int(packetsPerBuffer))
    }
    else {
        packetsPerBuffer = outputBufferSize / sizePerPacket
    }
    
    // allocate destination buffer
    let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: MemoryLayout<UInt8>.size * Int(outputBufferSize))
    var outputFilePacketPosition: UInt32 = 0
    while(true) {
        // wrap the destination buffer in an AudioBufferList
        let convertedData = AudioBufferList.allocate(maximumBuffers: 1)
        convertedData[0].mNumberChannels = mySettings.inputFormat.mChannelsPerFrame
        convertedData[0].mDataByteSize = outputBufferSize
        convertedData[0].mData = UnsafeMutableRawPointer(outputBuffer)
        
        // now call the audioConverter to transcode the data. This function will call
        // the callback function as many times as required to fullfill the request
        var ioOutputDataPackets: UInt32 = packetsPerBuffer
        let error: OSStatus = AudioConverterFillComplexBuffer(audioConverter,
                                                              myAudioConverterCallback,
                                                              &mySettings,
                                                              &ioOutputDataPackets,
                                                              convertedData.unsafeMutablePointer,
                                                              (mySettings.inputFilePacketDescriptions != nil) ? mySettings.inputFilePacketDescriptions : nil)
        if (error != noErr || 0 == ioOutputDataPackets) {
            break // this is out termination condition
        }
        
        // write the converted data to the output file
        CheckError(AudioFileWritePackets(mySettings.outputFile!,
                              false,
                              ioOutputDataPackets,
                              nil,
                              Int64(outputFilePacketPosition / mySettings.outputFormat.mBytesPerPacket),
                              &ioOutputDataPackets,
                              convertedData[0].mData!), "Couldn't write packets to file")
        
        // advance the output file write location
        outputFilePacketPosition += (ioOutputDataPackets * mySettings.outputFormat.mBytesPerPacket)
    }
    
    AudioConverterDispose(audioConverter)
    outputBuffer.deallocate()
}

var audioConverterSettings = MyAudioConverterSettings()

// open the input audio file
let inputFileURL = URL(fileURLWithPath: kInputFileLocation)
CheckError(AudioFileOpenURL(inputFileURL as CFURL,
                 AudioFilePermissions.readPermission,
                 0,
                 &audioConverterSettings.inputFile), "AudioFileOpenURL failed")

guard let inputFile = audioConverterSettings.inputFile else {
    debugPrint("Couldn't get inputFile from audioConverterSettings")
    exit(-1)
}

// get the audio data format from the file
var propSize: UInt32 = UInt32(MemoryLayout.size(ofValue: audioConverterSettings.inputFormat))
CheckError(AudioFileGetProperty(inputFile,
                     kAudioFilePropertyDataFormat,
                     &propSize,
                     &audioConverterSettings.inputFormat), "couldn't get file's data format")

// get the total number of packets in the file
propSize = UInt32(MemoryLayout.size(ofValue: audioConverterSettings.inputFilePacketCount))
CheckError(AudioFileGetProperty(inputFile,
                     kAudioFilePropertyAudioDataPacketCount,
                     &propSize,
                     &audioConverterSettings.inputFilePacketCount), "couldn't get file's packet count")

// get size of the largest possible packet
propSize = UInt32(MemoryLayout.size(ofValue: audioConverterSettings.inputFilePacketMaxSize))
CheckError(AudioFileGetProperty(inputFile,
                     kAudioFilePropertyMaximumPacketSize,
                     &propSize,
                     &audioConverterSettings.inputFilePacketMaxSize), "couldn't get file's max packet size")

// define the output format. AudioConverter requires that one of the data formats be LPCM
audioConverterSettings.outputFormat.mSampleRate = 44100.0
audioConverterSettings.outputFormat.mFormatID = kAudioFormatLinearPCM
audioConverterSettings.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
audioConverterSettings.outputFormat.mBytesPerPacket = 4
audioConverterSettings.outputFormat.mFramesPerPacket = 1
audioConverterSettings.outputFormat.mBytesPerFrame = 4
audioConverterSettings.outputFormat.mChannelsPerFrame = 2
audioConverterSettings.outputFormat.mBitsPerChannel = 16

// create output file
let outputFileURL = URL(fileURLWithPath: "output.aif")
CheckError(AudioFileCreateWithURL(outputFileURL as CFURL,
                       kAudioFileAIFFType,
                       &audioConverterSettings.outputFormat,
                       AudioFileFlags.eraseFile,
                       &audioConverterSettings.outputFile), "AudioFileCreateWithURL failed")

debugPrint("Converting...")
Convert(&audioConverterSettings)

AudioFileClose(audioConverterSettings.inputFile!)
AudioFileClose(audioConverterSettings.outputFile!)
debugPrint("Done")

