//
//  AppDelegate.swift
//  CH10_iOSBackgroundingTone_Swift
//
//  Created by LEE CHIEN-MING on 18/03/2017.
//  Copyright © 2017 derekli66. All rights reserved.
//

import UIKit
import AudioToolbox

private func CheckError(_ error: OSStatus, operation: String) {
    
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

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        let status: OSStatus = 0x41424344
        CheckError(status, operation: "[TEST]")
        
        return true;
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

