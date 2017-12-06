//
//  OpenALErrorCheck.swift
//  CH09_OpenALOrbitStream-Swift
//
//  Created by LEE CHIEN-MING on 23/11/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation
import OpenAL

// MARK:- Error Check
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
