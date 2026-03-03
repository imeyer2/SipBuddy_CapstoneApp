//
//  FR2ParsersTests.swift
//  CapstoneAppTests
//
//  Unit tests for FR2Parsers: SigFinder, BUFHeaderParser, FR2Assembler
//

#if canImport(XCTest)
import Foundation
import XCTest
@testable import CapstoneApp

final class FR2ParsersTests: XCTestCase {

    // MARK: - SigFinder
    func testSigFinderBasic() {
        var f = SigFinder("BUF")
        var hits = 0
        let bytes = Array("xxBUFyy".utf8)
        for b in bytes { if f.feed(b) { hits += 1 } }
        XCTAssertEqual(hits, 1)
    }

    func testSigFinderOverlapping() {
        var f = SigFinder("ABA")
        var hits = 0
        let bytes = Array("ABABA".utf8)
        for b in bytes { if f.feed(b) { hits += 1 } }
        // Two matches: positions ending at index 2 and 4 (0-based)
        XCTAssertEqual(hits, 2)
    }

    // MARK: - BUFHeaderParser
    func testBUFHeaderValidAcrossChunks() {
        let w: UInt16 = 300 // 0x012C
        let h: UInt16 = 240 // 0x00F0
        let c: UInt32 = 3
        var header = Data()
        header.append(contentsOf: [0x42, 0x55, 0x46]) // "BUF"
        header.append(contentsOf: [UInt8(w >> 8), UInt8(w & 0xFF)])
        header.append(contentsOf: [UInt8(h >> 8), UInt8(h & 0xFF)])
        header.append(contentsOf: [UInt8((c >> 24) & 0xFF), UInt8((c >> 16) & 0xFF), UInt8((c >> 8) & 0xFF), UInt8(c & 0xFF)])

        let noise1 = Data([0x00, 0x11, 0x22, 0x42]) // ends with 'B' (0x42)
        let noise2 = Data([0x55]) // 'U'
        let chunk3 = Data([0x46]) + header.dropFirst(3).prefix(5) // completes to some of the fixed tail
        let chunk4 = Data(header.suffix(from: 8)) + Data([0xDE, 0xAD, 0xBE, 0xEF]) // rest of header + extra trailing bytes

        let p = BUFHeaderParser()
        let used1 = p.consume(noise1)
        XCTAssertEqual(used1, noise1.count)
        XCTAssertFalse(p.haveHeader)

        _ = p.consume(noise2)
        // No header yet (we've only seen "BU" via noise + noise2)
        XCTAssertFalse(p.haveHeader)

        let used3 = p.consume(chunk3)
        XCTAssertFalse(p.haveHeader)
        XCTAssertGreaterThan(used3, 0)

        let used4 = p.consume(chunk4)
        XCTAssertTrue(p.haveHeader)
        XCTAssertEqual(p.width, Int(w))
        XCTAssertEqual(p.height, Int(h))
        XCTAssertEqual(p.count, Int(c))
        // Parser should consume only up to 11 bytes past the signature; extra bytes remain
        XCTAssertLessThanOrEqual(used4, chunk4.count)
    }

    func testBUFHeaderIncomplete() {
        let p = BUFHeaderParser()
        let partial = Data("BU".utf8) // never completes to BUF
        let used = p.consume(partial)
        XCTAssertEqual(used, partial.count)
        XCTAssertFalse(p.haveHeader)
    }

    // MARK: - FR2Assembler
    func testFR2AssemblerValid() throws {
        // Build FR2 header: "FR2" + >H w + >H h + >I size + B pixfmt + >H frameID
        let w: UInt16 = 0x0100 // 256
        let h: UInt16 = 0x0080 // 128
        let size: UInt32 = 5
        let pix: UInt8 = 1
        let fid: UInt16 = 7

        var hdr = Data()
        hdr.append(contentsOf: [0x46, 0x52, 0x32]) // FR2
        hdr.append(contentsOf: [UInt8(w >> 8), UInt8(w & 0xFF)])
        hdr.append(contentsOf: [UInt8(h >> 8), UInt8(h & 0xFF)])
        hdr.append(contentsOf: [UInt8((size >> 24) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)])
        hdr.append(pix)
        hdr.append(contentsOf: [UInt8(fid >> 8), UInt8(fid & 0xFF)])

        let payload = Data([0xFF, 0xD8, 0x00, 0x01, 0x02]) // arbitrary bytes

        let a = FR2Assembler()
        // Feed in fragmented manner
        var used = a.consume(Data([0x00, 0x11, 0x22, 0x46])) // finds 'F'
        XCTAssertGreaterThan(used, 0)
        used = a.consume(Data([0x52])) // 'R'
        XCTAssertEqual(used, 1)
        used = a.consume(Data([0x32]) + hdr.dropFirst(3).prefix(5))
        XCTAssertGreaterThan(used, 0)
        // Complete header and start payload
        used = a.consume(Data(hdr.suffix(from: 8)) + payload.prefix(2))
        XCTAssertGreaterThan(used, 0)
        XCTAssertFalse(a.done)
        // Finish payload
        used = a.consume(payload.suffix(from: 2))
        XCTAssertTrue(a.done)
        let out = a.takeJPEG()
        let data = try XCTUnwrap(out)
        XCTAssertEqual(data, payload)
        // After takeJPEG, assembler is reset
        XCTAssertFalse(a.done)
    }

    func testFR2AssemblerZeroSize() throws {
        let w: UInt16 = 1
        let h: UInt16 = 1
        let size: UInt32 = 0
        let pix: UInt8 = 0
        let fid: UInt16 = 0

        var hdr = Data()
        hdr.append(contentsOf: [0x46, 0x52, 0x32])
        hdr.append(contentsOf: [UInt8(w >> 8), UInt8(w & 0xFF)])
        hdr.append(contentsOf: [UInt8(h >> 8), UInt8(h & 0xFF)])
        hdr.append(contentsOf: [UInt8((size >> 24) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)])
        hdr.append(pix)
        hdr.append(contentsOf: [UInt8(fid >> 8), UInt8(fid & 0xFF)])

        let a = FR2Assembler()
        _ = a.consume(hdr)
        XCTAssertTrue(a.done)
        let out = a.takeJPEG()
        let data = try XCTUnwrap(out)
        XCTAssertEqual(data.count, 0)
    }

    func testFR2AssemblerInvalidAndPostDone() {
        let a = FR2Assembler()
        // Feed random noise; should not be done
        var used = a.consume(Data([0x00, 0x01, 0x02, 0x03]))
        XCTAssertEqual(used, 4)
        XCTAssertFalse(a.done)
        // Manually set to done via zero-size header, then ensure further consume returns 0
        var hdr = Data([0x46, 0x52, 0x32])
        hdr.append(contentsOf: [0x00, 0x01, 0x00, 0x01]) // w=1,h=1
        hdr.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // size=0
        hdr.append(0x00)
        hdr.append(contentsOf: [0x00, 0x01])
        _ = a.consume(hdr)
        XCTAssertTrue(a.done)
        used = a.consume(Data([0xAA, 0xBB]))
        XCTAssertEqual(used, 0)
    }
}
#endif
