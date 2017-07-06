//
//  main.swift
//  CH11_MIDIToAUGraph-Swift
//
//  Created by LEE CHIEN-MING on 21/05/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import CoreFoundation
import Foundation
import CoreMIDI
import AudioToolbox

typealias Byte = UInt8

struct MyMIDIPlayer
{
    var graph: AUGraph?
    var instrumentUnit: AudioUnit?
    var client: MIDIClientRef = 0
    var inputPort: MIDIPortRef = 0
}

// MARK: - Callbacks
let MyMIDIReadProc: MIDIReadProc = {
    (pktlist: UnsafePointer<MIDIPacketList>,
    readProcRefCon: UnsafeMutableRawPointer?,
    srcConnRefCon: UnsafeMutableRawPointer?) in

    guard let refCon = readProcRefCon else {
        debugPrint("There is no reference pointer to MyMIDIPlayer")
        return
    }
    
    let player: MyMIDIPlayer = refCon.bindMemory(to: MyMIDIPlayer.self, capacity: 1).pointee
    var packetList: MIDIPacketList = pktlist.pointee
    var packet: UnsafeMutablePointer<MIDIPacket> = UnsafeMutablePointer(&packetList.packet)
    let numPackets: UInt32 = packetList.numPackets
    
    guard let instrumentUnit = player.instrumentUnit else {
        debugPrint("There is no instrument unit for playing MIDI")
        return
    }
    
    for idx in 0..<numPackets {
        var midiStatus: Byte = packet.pointee.data.0
        var midiCommand: Byte = midiStatus >> 4
        
        // is it a note-on or note-off
        if (midiCommand == 0x09 || midiCommand == 0x08) {
            var note: Byte = packet.pointee.data.1 & 0x7F
            var velocity: Byte = packet.pointee.data.2 & 0x7F
            debugPrint("midiCommand=\(midiCommand). Note=\(note), Velocity=\(velocity)")
            
            // Send to augraph
            CheckError(MusicDeviceMIDIEvent(instrumentUnit,
                                 UInt32(midiStatus),
                                 UInt32(note),
                                 UInt32(velocity),
                                 0), "Couldn't send MIDI event")
        }
        
        packet = MIDIPacketNext(packet)
    }
}

private func connectMIDISource(_ inputPort: MIDIPortRef) -> Void
{
    let sourceCount = MIDIGetNumberOfSources()
    debugPrint("\(sourceCount) sources")
    
    for idx in 0..<sourceCount {
        let src: MIDIEndpointRef = MIDIGetSource(idx)
        var endpointName: Unmanaged<CFString>?
        CheckError(MIDIObjectGetStringProperty(src,
                                               kMIDIPropertyName,
                                               &endpointName), "Couldn't get endpoint name")
        
        var buffer: Array<CChar> = Array<CChar>(repeating: 0, count: 255)
        CFStringGetCString(endpointName?.takeUnretainedValue(),
                           &buffer,
                           255,
                           CFStringEncoding(String.Encoding.utf8.rawValue))
        
        buffer.withUnsafeBufferPointer({ ptr in
            let endpoint_name = String(cString: ptr.baseAddress!)
            debugPrint("    source \(idx): \(endpoint_name)")
        })
        
        CheckError(MIDIPortConnectSource(inputPort, src, nil), "Couldn't connect MIDI port")
    }
}

let MyMIDINotifyProc: MIDINotifyProc = { (message: UnsafePointer<MIDINotification>, refCon: UnsafeMutableRawPointer?) in
    debugPrint("MIDI Notify, messageId=\(message.pointee.messageID)")
    
    switch message.pointee.messageID {
    case .msgSetupChanged:
        debugPrint("msgSetupChanged")
        guard let refCon = refCon else {
            debugPrint("There is no reference pointer to MyMIDIPlayer")
            break
        }
        
        let player: MyMIDIPlayer = refCon.bindMemory(to: MyMIDIPlayer.self, capacity: 1).pointee
        
        // Reconnect if MIDI session setup was changed
        connectMIDISource(player.inputPort)
        
    case .msgObjectAdded:
        debugPrint("msgObjectAdded")
    case .msgObjectRemoved:
        debugPrint("msgObjectRemoved")
    case .msgPropertyChanged:
        debugPrint("msgPropertyChanged")
    case .msgThruConnectionsChanged:
        debugPrint("msgThruConnectionsChanged")
    case .msgSerialPortOwnerChanged:
        debugPrint("msgSerialPortOwnerChanged")
    case .msgIOError:
        debugPrint("msgIOError")
    }
}

// MARK:- AUGraph
func setupAUGraph(_ player: inout MyMIDIPlayer)
{
    CheckError(NewAUGraph(&player.graph), "Couldn't open AU Graph")
    
    guard let graph = player.graph else {
        debugPrint("Couldn't get AU graph")
        return
    }
    
    // generate description that will match out output device (speakers)
    var outputcd = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                             componentSubType: kAudioUnitSubType_DefaultOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0,
                                             componentFlagsMask: 0)
    
    // adds a node with above description to the graph
    var outputNode: AUNode = 0
    CheckError(AUGraphAddNode(graph,
                   &outputcd,
                   &outputNode), "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed")
    
    var instrumentcd = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                                 componentSubType: kAudioUnitSubType_DLSSynth,
                                                 componentManufacturer: kAudioUnitManufacturer_Apple,
                                                 componentFlags: 0,
                                                 componentFlagsMask: 0)
    var instrumentNode: AUNode = 0
    CheckError(AUGraphAddNode(graph, &instrumentcd, &instrumentNode), "AUGraphAddNode[kAudioUnitSubType_DLSSynth] failed")
    
    // opening the graph opens all contained audio units but does not allocate any resources yet
    CheckError(AUGraphOpen(graph), "AUGraphOpen failed")
    
    // get the reference to the AudioUnit object for the instrument graph node
    CheckError(AUGraphNodeInfo(graph, instrumentNode, nil, &player.instrumentUnit), "AUGraphNodeInfo failed")
    
    // connect the output source of the instrument AU to the input source of the output node
    CheckError(AUGraphConnectNodeInput(graph, instrumentNode, 0, outputNode, 0), "AUGraphConnectNodeInput")
    
    // now initialize the graph (causes resources to be allocated)
    CheckError(AUGraphInitialize(graph), "AUGraphInitialize failed")
}

// MARK:- MIDI
func setupMIDI(_ player: inout MyMIDIPlayer) -> Void
{
    var client: MIDIClientRef = 0
    CheckError(MIDIClientCreate(("Core MIDI to System Sounds Demo" as CFString),
                     MyMIDINotifyProc,
                     &player,
                     &client), "Couln't create MIDI client")
    
    player.client = client
    
    var inPort: MIDIPortRef = 0
    CheckError(MIDIInputPortCreate(client,
                        ("Input port" as CFString),
                        MyMIDIReadProc,
                        &player,
                        &inPort), "Couldn't create MIDI input port")
    
    player.inputPort = inPort
    
    connectMIDISource(inPort)
}

// MARK: - main
var player: MyMIDIPlayer = MyMIDIPlayer()
setupAUGraph(&player)
setupMIDI(&player)

guard let graph = player.graph else {
    exit(-1)
}

debugPrint("Ready to start AUGraph")
CheckError(AUGraphStart(graph), "Couldn't start graph")

CFRunLoopRun()

