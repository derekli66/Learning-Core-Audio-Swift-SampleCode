//
//  OSStatus_ErrorCheck.swift
//  CH10_iOSPlayThrough-swift
//
//  Created by LEE CHIEN-MING on 02/04/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation

public func CheckError(_ error: OSStatus, _ operation: String) -> Void
{
    if (error == noErr) { return }
    
    let count = 5
    let stride = MemoryLayout<OSStatus>.stride
    let byteCount = stride * count
    
    var error_ =  CFSwapInt32HostToBig(UInt32(error))
    var charArray: [CChar] = [CChar](repeating: 0, count: byteCount )
    withUnsafeBytes(of: &error_) { (buffer: UnsafeRawBufferPointer) in
        for (index, byte) in buffer.enumerated() {
            charArray[index + 1] = CChar(byte)
        }
    }
    
    let v1 = charArray[1], v2 = charArray[2], v3 = charArray[3], v4 = charArray[4]
    
    if (isprint(Int32(v1)) > 0 && isprint(Int32(v2)) > 0 && isprint(Int32(v3)) > 0 && isprint(Int32(v4)) > 0) {
        charArray[0] = "\'".utf8CString[0]
        charArray[5] = "\'".utf8CString[0]
        let errStr = NSString(bytes: &charArray, length: charArray.count, encoding: String.Encoding.ascii.rawValue)
        print("Error: \(operation) (\(errStr!))")
    }
    else {
        print("Error: \(error)")
    }
    
    exit(1)
}
