//
//  AppDelegate.swift
//  CH10_iOSPlayThrough-swift
//
//  Created by LEE CHIEN-MING on 01/04/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import UIKit
import AudioToolbox
import AVFoundation

class EffectState
{
    var rioUnit: AudioUnit?
    var asbd: AudioStreamBasicDescription = AudioStreamBasicDescription()
    var sineFrequency: Double = 0
    var sinePhase: Double = 0
}

private let MyInterruptionListener: AudioSessionInterruptionListener = {
    (inClientData: UnsafeMutableRawPointer? , inInterruptionState: UInt32) in
    
    print("Interrupted! inInterruptionState=\(inInterruptionState)")
    guard let clientData = inClientData else { return }
    
    let appDelegate = Unmanaged<CH10_iOSPlayThroughAppDelegate>.fromOpaque(clientData).takeUnretainedValue()
    
    switch Int(inInterruptionState) {
    case kAudioSessionBeginInterruption:
        print("Audio session begins interruption")
    case kAudioSessionEndInterruption:
        print("Audio session ends interruption")
        let unit: AudioUnit = appDelegate.effectState.rioUnit!
        CheckError(AudioUnitInitialize(unit), "Couldn't initialize RIO unit")
    default: break
        
    }
}

private let InputModulatingRenderCallback: AURenderCallback = {
    (inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?) in

    let effectState = Unmanaged<EffectState>.fromOpaque(inRefCon).takeUnretainedValue()
    
    guard let remoteIOUnit = effectState.rioUnit,
          let ioData_ = ioData else {
        debugPrint("There is no remote IO unit for rendering")
        return kAudioUnitErr_InvalidOfflineRender
    }
    
    // just copy samples
    let bus1: UInt32 = 1
    
    CheckError(AudioUnitRender(remoteIOUnit,
                    ioActionFlags,
                    inTimeStamp,
                    bus1,
                    inNumberFrames,
                    ioData_),
               "Couldn't render from RemoteIO unit")
    
    // walk the samples
    var sample: Int16 = 0
    let bytesPerChannel = effectState.asbd.mBytesPerFrame/effectState.asbd.mChannelsPerFrame
    
    let abl = UnsafeMutableAudioBufferListPointer(ioData_)
    
    for buf in abl {
        guard let mData = buf.mData else { continue }
        
        var currentFrame: UInt32 = 0
        
        while currentFrame < inNumberFrames {
            // copy sample to buffer, across all channels
            
            for currentChannel in 0..<buf.mNumberChannels {
                
                let framePosition = (currentFrame * effectState.asbd.mBytesPerFrame) + (currentChannel * bytesPerChannel)
                let framePtr = mData.advanced(by: Int(framePosition))
                memcpy(&sample, framePtr, MemoryLayout<Int16>.size)
                
                let theta = effectState.sinePhase * Double.pi * 2
                
                sample = Int16(sin(theta) * Double(sample))
                
                memcpy(framePtr, &sample, MemoryLayout<Int16>.size)
                
                effectState.sinePhase += 1.0 / (effectState.asbd.mSampleRate / effectState.sineFrequency)
                if (effectState.sinePhase > 1.0) {
                    effectState.sinePhase -= 1.0;
                }
            }
            currentFrame += 1;
        }
    }
    
    return noErr
}

@UIApplicationMain
class CH10_iOSPlayThroughAppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var effectState: EffectState = EffectState()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Set up audio session
        let audioSession = AVAudioSession.sharedInstance()
        do  {
            try audioSession.setActive(true)
            try audioSession.setCategory(AVAudioSession.Category.playAndRecord)
        }
        catch {
            // Print error after an exception throws
            debugPrint("Activating audio session failed. Error: \(error)")
        }
        
        // is audio input available
        if (!audioSession.isInputAvailable) {
            let alert: UIAlertController = UIAlertController(title: "No audio input",
                                                             message: "No audio input device is currently attached",
                                                             preferredStyle: UIAlertController.Style.alert)
            let action: UIAlertAction = UIAlertAction(title: "OK",
                                                      style: UIAlertAction.Style.default,
                                                      handler: { (action: UIAlertAction) in })
            alert.addAction(action)
            self.window?.rootViewController?.present(alert, animated: true)
            return true
        }
        
        // inspect hardware samplerate
        let preferredSampleRate = audioSession.preferredSampleRate
        debugPrint("hardwareSampleRate = \(preferredSampleRate)")
        
        // describe unit
        var audioComponentDesc: AudioComponentDescription =
            AudioComponentDescription(componentType: kAudioUnitType_Output,
                                      componentSubType: kAudioUnitSubType_RemoteIO,
                                      componentManufacturer: kAudioUnitManufacturer_Apple,
                                      componentFlags: 0,
                                      componentFlagsMask: 0)

        // Get RemoteIO unit from audio component manager
        let rioComponent: AudioComponent = AudioComponentFindNext(nil, &audioComponentDesc)!
        var audio_unit: AudioUnit?
        CheckError(AudioComponentInstanceNew(rioComponent, &audio_unit), "Couldn't get RemoteIO unit instance")
        
        guard let remoteIOUnit = audio_unit else {
            debugPrint("Couldn't get audio unit instance")
            return true
        }
        
        self.effectState.rioUnit = remoteIOUnit
        
        // Set up the RemoteIO unit for playback
        var oneFlag: UInt32 = 1
        let bus0: AudioUnitElement = 0
        CheckError(AudioUnitSetProperty(remoteIOUnit,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output,
                             bus0,
                             &oneFlag,
                             UInt32(MemoryLayout.size(ofValue: oneFlag)))
                   , "Couldn't enable remote IO output")
        
        // Enable remote IO input
        let bus1: AudioUnitElement = 1
        CheckError(AudioUnitSetProperty(remoteIOUnit,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input,
                             bus1,
                             &oneFlag,
                             UInt32(MemoryLayout.size(ofValue: oneFlag)))
                   , "Couldn't enable remote IO input")
        
        // Set up an asbd in the iphone canonical format
        var myASBD: AudioStreamBasicDescription =
            AudioStreamBasicDescription(mSampleRate: preferredSampleRate,
                                        mFormatID: kAudioFormatLinearPCM,
                                        mFormatFlags: kAudioFormatFlagsCanonical,
                                        mBytesPerPacket: 4,
                                        mFramesPerPacket: 1,
                                        mBytesPerFrame: 4,
                                        mChannelsPerFrame: 2,
                                        mBitsPerChannel: 16,
                                        mReserved: 0)
        
        // Set format for output (bus 0) on remote IO's input scope
        CheckError(AudioUnitSetProperty(remoteIOUnit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input,
                             bus0,
                             &myASBD,
                             UInt32(MemoryLayout.size(ofValue: myASBD))),
                   "Couldn't set ASBD for RIO on input scope/ bus 0")
        
        // set asbd for mic input
        CheckError(AudioUnitSetProperty(remoteIOUnit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output,
                             bus1,
                             &myASBD,
                             UInt32(MemoryLayout.size(ofValue: myASBD))),
                   "Couldn't set ASBD for RIO on output scope / bus 1")
        
        // more info on ring modulator and dalek voices at:
        // http://homepage.powerup.com.au/~spratleo/Tech/Dalek_Voice_Primer.html
        self.effectState.asbd = myASBD
        self.effectState.sineFrequency = 30
        self.effectState.sinePhase = 0
        
        // set callback method
        var callbackStruct: AURenderCallbackStruct =
            AURenderCallbackStruct(inputProc: InputModulatingRenderCallback,
                                   inputProcRefCon: Unmanaged.passUnretained(self.effectState).toOpaque())
        
        CheckError(AudioUnitSetProperty(remoteIOUnit,
                             kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Global,
                             bus0,
                             &callbackStruct,
                             UInt32(MemoryLayout.size(ofValue: callbackStruct))),
                   "Couldn't set RIO render callback on bus 0")
        
        // initialize and start remoteIO unit
        CheckError(AudioUnitInitialize(remoteIOUnit), "Couldn't initialize RIO unit")
        CheckError(AudioOutputUnitStart(remoteIOUnit), "Couldn't start RIO unit")
        
        debugPrint("RIO started!")
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}

