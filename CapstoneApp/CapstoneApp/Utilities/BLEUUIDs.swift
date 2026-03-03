//
//  BLEUUIDs.swift
//  SipBuddy
//
//


import Foundation
import CoreBluetooth

enum BLEUUIDs {
    // Nordic UART Service (plus extra characteristics as per your unit test)
    static let service = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let txText = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")  // Notify
    static let txFrame = CBUUID(string: "6E400005-B5A3-F393-E0A9-E50E24DCCA9E") // Notify (binary frames)
    static let rxBasic = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")  // Write (PING/START/STOP)
    static let rxCam   = CBUUID(string: "6E400004-B5A3-F393-E0A9-E50E24DCCA9E")  // Write (camera config)
    static let rxMode  = CBUUID(string: "6E400006-B5A3-F393-E0A9-E50E24DCCA9E")  // Write (STREAM/SLEEP/DETECT)
}