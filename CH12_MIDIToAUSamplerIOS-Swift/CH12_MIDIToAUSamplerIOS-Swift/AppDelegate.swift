//
//  AppDelegate.swift
//  CH12_MIDIToAUSamplerIOS-Swift
//
//  Created by LEE CHIEN-MING on 09/12/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import UIKit
import Foundation
import AudioToolbox
import CoreMIDI
import CoreFoundation

postfix operator ~>

class MyMIDIPlayer {
    var graph: AUGraph?
    var instrumentUnit: AudioUnit?
}

extension UnsafeMutablePointer where Pointee == MyMIDIPlayer {
    static postfix func ~>(_ pointer: UnsafeMutablePointer) -> MyMIDIPlayer {
        return pointer.pointee
    }
}

extension UnsafePointer where Pointee == MIDINotification {
    static postfix func ~>(_ pointer: UnsafePointer) -> MIDINotification {
        return pointer.pointee
    }
}

extension UnsafePointer where Pointee == MIDIPacketList {
    static postfix func ~>(_ pointer: UnsafePointer) -> MIDIPacketList {
        return pointer.pointee
    }
}

// MARK: - Proc
let MyMIDINotifyProc: MIDINotifyProc = {
    (message: UnsafePointer<MIDINotification>, refCon: UnsafeMutableRawPointer?) in
    debugPrint("MIDI Notify, messageId=\(message~>.messageID)")
}

let MyMIDIReadProc: MIDIReadProc = {
    (pktlist: UnsafePointer<MIDIPacketList>,
    readProcRefCon: UnsafeMutableRawPointer?,
    srcConnRefCon: UnsafeMutableRawPointer?) in
    
    guard let refCon = readProcRefCon else { return }
    
    let player: MyMIDIPlayer = refCon.bindMemory(to: MyMIDIPlayer.self, capacity: 1)~>
    var packet: MIDIPacket = pktlist~>.packet
    
    for _ in 0..<pktlist~>.numPackets {
        let midiStatus: UInt8 = packet.data.0
        let midiCommand: UInt8 = midiStatus >> 4
        // is it a note-on or note-off
        if ((0x09 == midiCommand) || (0x08 == midiCommand)) {
            let note: UInt8 = packet.data.1 & 0x7F
            let velocity: UInt8 = packet.data.2 & 0x7F
            debugPrint("midiCommand=\(midiCommand). Note=\(note). Velocity=\(velocity)")
            
            // send to AUGraph
            CheckError(MusicDeviceMIDIEvent(player.instrumentUnit!,
                                            UInt32(midiStatus),
                                            UInt32(note),
                                            UInt32(velocity),
                                            0), "Couldn't send MIDI event")
        }
        packet = MIDIPacketNext(&packet).pointee
    }
}

// MARK: - MIDI
func setupMIDI(_ player: MyMIDIPlayer) -> Void
{
    var player = player
    var client: MIDIClientRef = 0
    CheckError(MIDIClientCreate("Core MIDI to System Sounds Demo" as CFString,
                                MyMIDINotifyProc,
                                &player,
                                &client), "Couldn't create MIDI client")
    
    var inPort: MIDIPortRef = 0
    CheckError(MIDIInputPortCreate(client,
                                   "Input Port" as CFString,
                                   MyMIDIReadProc,
                                   &player,
                                   &inPort), "Couldn't create MIDI input port")
    
    let sourceCount = MIDIGetNumberOfSources()
    debugPrint("\(sourceCount) sources")
    
    for idx in 0..<sourceCount {
        let src: MIDIEndpointRef = MIDIGetSource(idx)
        var endpointName: Unmanaged<CFString>?
        CheckError(MIDIObjectGetStringProperty(src,
                                               kMIDIPropertyName,
                                               &endpointName), "Couldn't get endpoint name")
        
        let name = endpointName!.takeUnretainedValue()
        debugPrint("    source \(idx): \(name)")
        
        CheckError(MIDIPortConnectSource(inPort,
                                         src,
                                         nil), "Couldn't connect MIDI port")
    }
}

// MARK:- AUGraph
func setupAUGraph(_ player: MyMIDIPlayer) -> Void
{
    CheckError(NewAUGraph(&player.graph), "Couldn't open AU Graph")
    
    guard let graph = player.graph else { return }
    
    // generate description that will match our output device (speakers)
    var outputcd = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                             componentSubType: kAudioUnitSubType_RemoteIO,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0,
                                             componentFlagsMask: 0)
    
    // adds a node with above description to the graph
    var outputNode: AUNode = 0
    CheckError(AUGraphAddNode(graph,
                              &outputcd,
                              &outputNode),
               "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed")
    
    var instrumentcd = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                                 componentSubType: kAudioUnitSubType_Sampler,
                                                 componentManufacturer: kAudioUnitManufacturer_Apple,
                                                 componentFlags: 0,
                                                 componentFlagsMask: 0)
    var instrumentNode: AUNode = 0
    CheckError(AUGraphAddNode(graph, &instrumentcd, &instrumentNode),
               "AUGraphAddNode[kAudioUnitSubType_Sampler] failed")
    
    // opening the graph opens all contained audio units but does not allocate any resources yet
    CheckError(AUGraphOpen(graph), "AUGraphOpen failed")
    
    // get the reference to the AudioUnit object for the instrument graph node
    CheckError(AUGraphNodeInfo(graph,
                               instrumentNode,
                               nil,
                               &player.instrumentUnit), "AUGraphNodeInfo failed")
    
    // connect the output source of the instrument AU to the input source of the output node
    CheckError(AUGraphConnectNodeInput(graph,
                                       instrumentNode,
                                       0,
                                       outputNode,
                                       0), "AUGraphConnectNodeInput failed")
    
    // now initialize the graph (causes resources to be allocated)
    CheckError(AUGraphInitialize(graph), "AUGraphInitialize failed")
    
    // configure the AUSampler
    // 2nd parameter obviously needs to be a full path on your system,
    // and 3rd param is its length in characters
    let presetURL = Bundle.main.url(forResource: "ch12-aupreset", withExtension: "aupreset")
    
    print("presetPath: \(presetURL!.absoluteString)")
    
    let presetData = try? Data(contentsOf: presetURL!)
    
    if (presetData == nil) {
        print("Couldn't load .aupreset data")
        return
    }
    
    var presetPlistFormat: CFPropertyListFormat = CFPropertyListFormat.openStepFormat
    var presetPlistError: Unmanaged<CFError>?
    let presetPlist = CFPropertyListCreateWithData(kCFAllocatorSystemDefault,
                                                   presetData! as CFData,
                                                   0,
                                                   &presetPlistFormat,
                                                   &presetPlistError)
    
    if (presetPlistError != nil) {
        print("Couldn't create plist object for .aupreset")
        return;
    }
    
    if (presetPlist != nil) {
        var presetPlistData = presetPlist!.takeUnretainedValue()
        CheckError(AudioUnitSetProperty(player.instrumentUnit!,
                                        kAudioUnitProperty_ClassInfo,
                                        kAudioUnitScope_Global,
                                        0,
                                        &presetPlistData,
                                        UInt32(sizeof(presetPlist))), "Couldn't set aupreset plist as sampler's class info")
    }
    
    print("AUGraph ready")
//    CAShow(UnsafeMutablePointer<AUGraph>(player.graph!))
}


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var player: MyMIDIPlayer = MyMIDIPlayer()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        setupAUGraph(player)
        setupMIDI(player)
        CheckError(AUGraphStart(player.graph!), "Couldn't start graph")
        
        print("MIDI app running")
        
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

