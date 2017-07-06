//
//  ViewController.swift
//  CH11_MIDIWifiSource-Swift
//
//  Created by LEE CHIEN-MING on 22/05/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import UIKit
import CoreMIDI

typealias Byte = UInt8

private let DESTINATION_ADDRESS = "192.168.2.104"

class ViewController: UIViewController {
    
    fileprivate var midiSession: MIDINetworkSession?
    fileprivate var destinationEndPoint: MIDIEndpointRef?
    fileprivate var outputPort: MIDIPortRef?
    
    // Private
    private func connectToHost() -> Void
    {
        let host: MIDINetworkHost = MIDINetworkHost(name: "MyMIDIWifi", address: DESTINATION_ADDRESS, port: 5004)
        let connection: MIDINetworkConnection = MIDINetworkConnection(host: host)
        
        midiSession = MIDINetworkSession.default();
        midiSession?.addConnection(connection)
        midiSession?.isEnabled = true
        destinationEndPoint = self.midiSession?.destinationEndpoint()
        
        var client: MIDIClientRef = 0
        var outport: MIDIPortRef =  0
        CheckError(MIDIClientCreate("MyMIDIWifi client" as CFString, nil, nil, &client),
                   "Couldn't create MIDI client")
        CheckError(MIDIOutputPortCreate(client, "MyMIDIOutputPort" as CFString, &outport),
                   "Couldn't create output port")
        self.outputPort = outport
        debugPrint("Got output port")
    }
    
    private func sendStatus(_ status: Byte, data1: Byte, data2: Byte) -> Void
    {
        let packetListPtr = UnsafeMutablePointer<MIDIPacketList>.allocate(capacity: 1)
        let midiDataToSend: [Byte] = [status, data1, data2]
        let packet: UnsafeMutablePointer<MIDIPacket> = MIDIPacketListInit(packetListPtr)
        _ = MIDIPacketListAdd(packetListPtr, 1024, packet, 0, 3, midiDataToSend)
        
        if let outputPort = outputPort, let destination = destinationEndPoint {
            MIDISend(outputPort, destination, packetListPtr)
        }
        else {
            debugPrint("Couldn't get outputPort and destinationEndPoint for sending MIDI event")
        }
        
        packetListPtr.deallocate(capacity: 1)
    }
    
    private func sendNoteOnEvent(_ key: Byte, velocity: Byte) -> Void
    {
        sendStatus(0x90, data1: key & 0x7F, data2: velocity & 0x7F)
    }
    
    private func sendNoteOffEvent(_ key: Byte, velocity: Byte) -> Void
    {
        sendStatus(0x80, data1: key & 0x7F, data2: velocity & 0x7F)
    }
    
    @IBAction func handleKeyDown(sender: Any)
    {
        let note = (sender as! UIButton).tag
        sendNoteOnEvent(Byte(note), velocity: 127)
    }
    
    @IBAction func handleKeyUp(sender: Any)
    {
        let note = (sender as! UIButton).tag
        sendNoteOffEvent(Byte(note), velocity: 127)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        connectToHost()
    }
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.portrait
    }
}

