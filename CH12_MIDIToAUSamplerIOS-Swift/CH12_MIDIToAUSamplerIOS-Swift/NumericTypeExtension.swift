//
//  NumericTypeExtension.swift
//  CH09_OpenALOrbitStream-Swift
//
//  Created by LEE CHIEN-MING on 23/11/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import Foundation

// MARK:- Int type transform
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

// MARK:- Int64 type transform
extension Int64 {
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

// MARK:- UInt32 type transform
extension UInt32 {
    func toInt() -> Int {
        return Int(self)
    }
    
    func toDouble() -> Double {
        return Double(self)
    }
}

extension Double {
    func toUInt32() -> UInt32 {
        return UInt32(self)
    }
}


// MARK:- Memory Size of Type
func sizeof<T>(_ instance: T) -> Int
{
    return MemoryLayout.size(ofValue: instance)
}

func sizeof<T>(_ type: T.Type) -> Int
{
    return MemoryLayout<T>.size
}
