//
//  GIFEncoder.swift
//  SipBuddy
//
//


import UIKit
import ImageIO
import MobileCoreServices
import UniformTypeIdentifiers

enum GIFEncoder {
    static func makeGIF(from images: [UIImage], fps: Int = 6) -> Data? {
        guard !images.isEmpty else { return nil }
        let frameDelay = max(0.02, 1.0 / Double(max(1, fps)))
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, images.count, nil) else { return nil }
        let loopProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        CGImageDestinationSetProperties(dest, loopProps)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]] as CFDictionary
        for img in images {
            if let cg = img.cgImage { CGImageDestinationAddImage(dest, cg, frameProps) }
        }
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
