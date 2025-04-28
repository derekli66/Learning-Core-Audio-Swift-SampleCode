//
//  main.swift
//  CH03_CAStreamFormatTester-Swift
//
//  Created by LEE CHIEN-MING on 22/07/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import AudioToolbox

// Convert UInt32 (formats, file types) to string
extension UInt32 {
    func toString() -> String? {
        var value = self
        let data = Data(bytes: &value, count: MemoryLayout.size(ofValue: value))
        return String(data: data, encoding: .utf8)
    }
}

func main() {
    // Setup the format query
    var fileTypeAndFormat = AudioFileTypeAndFormatID(
        mFileType: kAudioFileAIFFType,
        mFormatID: kAudioFormatLinearPCM
    )
    
    // Get the size needed for format descriptions
    var infoSize: UInt32 = 0
    var status = AudioFileGetGlobalInfoSize(
        kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
        UInt32(MemoryLayout.size(ofValue: fileTypeAndFormat)),
        &fileTypeAndFormat,
        &infoSize
    )
    
    if status != noErr {
        let err4cc = CFSwapInt32HostToBig(UInt32(status))
        print("Error when getting size info: \(err4cc.toString() ?? String(status))")
        return
    }
    
    // Calculate how many descriptions we'll get
    let formatCount = Int(infoSize) / MemoryLayout<AudioStreamBasicDescription>.size
    
    // Allocate memory for the descriptions
    let asbds = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: formatCount)
    asbds.initialize(repeating: AudioStreamBasicDescription(), count: formatCount)
    
    defer {
        asbds.deinitialize(count: formatCount)
        asbds.deallocate()
    }
    
    // Get the actual format descriptions
    status = AudioFileGetGlobalInfo(
        kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
        UInt32(MemoryLayout.size(ofValue: fileTypeAndFormat)),
        &fileTypeAndFormat,
        &infoSize,
        asbds
    )
    
    if status != noErr {
        let err4cc = CFSwapInt32HostToBig(UInt32(status))
        print("Error getting formats: \(err4cc.toString() ?? String(status))")
        return
    }
    
    // Print all formats
    print("Available formats for AIFF/LinearPCM:")
    print("-------------------------------------")
    
    for idx in 0..<formatCount {
        let format4cc = CFSwapInt32HostToBig(asbds[idx].mFormatID)
        print("\(idx): mFormatId: \(format4cc.toString()!), mFormatFlags: \(asbds[idx].mFormatFlags), mBitsPerChannel: \(asbds[idx].mBitsPerChannel)")
    }
}

// Run the program
main()
