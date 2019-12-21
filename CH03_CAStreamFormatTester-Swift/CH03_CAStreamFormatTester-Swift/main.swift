//
//  main.swift
//  CH03_CAStreamFormatTester-Swift
//
//  Created by LEE CHIEN-MING on 22/07/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import AudioToolbox

func main()
{
    var fileTypeAndFormat = AudioFileTypeAndFormatID(mFileType: kAudioFileAIFFType,
                                                     mFormatID: kAudioFormatLinearPCM)
    
    var audioErr: OSStatus = noErr
    var infoSize: UInt32   = 0
    
    audioErr = AudioFileGetGlobalInfoSize(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                                          UInt32(MemoryLayout.size(ofValue: fileTypeAndFormat)),
                                          &fileTypeAndFormat,
                                          &infoSize)
    
    if (audioErr != noErr) {
        let err4cc = CFSwapInt32HostToBig(UInt32(audioErr))
        debugPrint("Error when getting size info: \(err4cc.toString()!)")
    }
    
    assert(audioErr == noErr)
    
    let asbds = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: Int(infoSize))
    asbds.initialize(repeating: AudioStreamBasicDescription(), count: Int(infoSize))
    defer {
        asbds.deinitialize(count: Int(infoSize))
        asbds.deallocate()
    }
    
    audioErr = AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                                      UInt32(MemoryLayout.size(ofValue: fileTypeAndFormat)),
                                      &fileTypeAndFormat,
                                      &infoSize,
                                      asbds)
    assert(audioErr == noErr)
    
    let asbdCount = Int(infoSize) / MemoryLayout<AudioStreamBasicDescription>.size
    for idx in 0..<asbdCount {
        let format4cc = CFSwapInt32HostToBig(asbds[idx].mFormatID)
        debugPrint("\(idx): mFormatId: \(format4cc.toString()!), mFormatFlags: \(asbds[idx].mFormatFlags), mBitsPerChannel: \(asbds[idx].mBitsPerChannel)")
    }
}

extension UInt32
{
    func toString() -> String?
    {
        var value = self
        let data = Data(bytes: &value, count: MemoryLayout.size(ofValue: value))
        return String(data: data, encoding: String.Encoding.utf8)
    }
}

// Perform main function
main()

