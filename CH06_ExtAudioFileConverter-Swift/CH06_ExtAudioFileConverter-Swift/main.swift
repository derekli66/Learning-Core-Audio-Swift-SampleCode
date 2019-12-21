//
//  main.swift
//  CH06_ExtAudioFileConverter-Swift
//
//  Created by LEE CHIEN-MING on 14/06/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import AudioToolbox

private let kInputFileLocation = "/Users/derekli/bitbucket/shape_of_you.mp3"

struct MyAudioConverterSettings
{
    var outputFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
    var inputFile: ExtAudioFileRef?
    var outputFile: AudioFileID?
}

// MARK: - Audio Converter
func Convert(_ mySettings: inout MyAudioConverterSettings)
{
    let outputBufferSize: UInt32 = 32 * 1024
    let sizePerPacket: UInt32 = mySettings.outputFormat.mBytesPerPacket
    let packetsPerBuffer: UInt32 = outputBufferSize / sizePerPacket
    
    // allocate destination buffer
    let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(outputBufferSize))
    outputBuffer.initialize(repeating: 0, count: Int(outputBufferSize))
    
    var outputFilePacketPosition: UInt32 = 0 // in bytes
    
    while (true) {
        // wrap the destination buffer in an AudioBufferList
        let convertedData: UnsafeMutableAudioBufferListPointer = AudioBufferList.allocate(maximumBuffers: 1)
        convertedData[0].mNumberChannels = mySettings.outputFormat.mChannelsPerFrame
        convertedData[0].mDataByteSize = outputBufferSize
        convertedData[0].mData = UnsafeMutableRawPointer(outputBuffer)
        
        var frameCount = packetsPerBuffer
        
        guard let inputFile = mySettings.inputFile else {
            debugPrint("No input source provided. Please specify one before converting audio file")
            break
        }
        
        // Read from the extaudio file
        CheckError(ExtAudioFileRead(inputFile,
                         &frameCount,
                         convertedData.unsafeMutablePointer), "Couldn't read from input file")
        
        if (0 == frameCount) {
            debugPrint("done reading from file")
            return
        }
        
        guard let outputFile = mySettings.outputFile else {
            debugPrint("There is no outputFile before converting audio file")
            return;
        }
        // write the converted data to the output file
        CheckError(AudioFileWritePackets(outputFile,
                              false,
                              frameCount * mySettings.outputFormat.mBytesPerPacket, // Weird part
                              nil,
                              Int64(outputFilePacketPosition / mySettings.outputFormat.mBytesPerPacket),
                              &frameCount,
                              convertedData[0].mData!), "Couldn't write packets to file")
        
        // advance the output file write location
        outputFilePacketPosition += (frameCount * mySettings.outputFormat.mBytesPerPacket)
        
        // free memory of AudioBufferList pointer
        free(convertedData.unsafeMutablePointer)
    }
    
    outputBuffer.deinitialize(count: Int(packetsPerBuffer))
    outputBuffer.deallocate()
}

var audioConverterSettings = MyAudioConverterSettings()

// open the input with ExtAudioFile
let inputFileURLRef = URL(fileURLWithPath: kInputFileLocation) as CFURL

CheckError(ExtAudioFileOpenURL(inputFileURLRef,
                    &audioConverterSettings.inputFile), "ExtAudioFileOpenURL failed")

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
let outputFileURLRef = URL(fileURLWithPath: "output.aif") as CFURL

CheckError(AudioFileCreateWithURL(outputFileURLRef,
                       kAudioFileAIFFType,
                       &audioConverterSettings.outputFormat,
                       AudioFileFlags.eraseFile,
                       &audioConverterSettings.outputFile), "AudioFileCreateWithURL failed")

CheckError(ExtAudioFileSetProperty(audioConverterSettings.inputFile!,
                        kExtAudioFileProperty_ClientDataFormat,
                        UInt32(Int(MemoryLayout<AudioStreamBasicDescription>.size)),
                        &audioConverterSettings.outputFormat), "Couldn't set client data format on input ext file")

debugPrint("Converting...")
Convert(&audioConverterSettings)

ExtAudioFileDispose(audioConverterSettings.inputFile!)
AudioFileClose(audioConverterSettings.outputFile!)


