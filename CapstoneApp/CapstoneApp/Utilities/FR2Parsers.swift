//
//  SigFinder.swift
//  SipBuddy
//
//


import Foundation

/// Streaming finder for a literal ASCII signature (e.g., \"BUF\" or \"FR2\").
struct SigFinder {
    let sig: [UInt8]
    private(set) var idx: Int = 0

    init(_ s: String) { self.sig = Array(s.utf8) }

    /// Feed bytes; returns true exactly once when the signature is matched ending at this byte.
    mutating func feed(_ byte: UInt8) -> Bool {
        if byte == sig[idx] {
            idx += 1
            if idx == sig.count { idx = 0; return true }
        } else {
            idx = (byte == sig[0]) ? 1 : 0
        }
        return false
    }
}



/// BUF header parser (tolerant):
///   \"BUF\" + >H w + >H h + >I count  (11 bytes total)
/// There may be extra bytes here (e.g., optional uint32 bytes_total); we ignore them
/// and start waiting for FR2 signature.
final class BUFHeaderParser {
    private var finder = SigFinder("BUF")
    private var buf = Data()
    private(set) var width: Int = 0
    private(set) var height: Int = 0
    private(set) var count: Int = 0
    private(set) var haveHeader = false

    func reset() { finder = SigFinder("BUF"); buf.removeAll(keepingCapacity: true); haveHeader = false }

    /// Feeds arbitrary chunk; returns bytes consumed. Sets haveHeader when 11 bytes following "BUF" are collected.
    func consume(_ chunk: Data) -> Int {
        var used = 0
        if !haveHeader {
            for b in chunk {
                used += 1
                if finder.feed(b) {
                    // seed with \"BUF\" already matched
                    buf = Data([0x42,0x55,0x46]) // \"BUF\"
                    break
                }
            }
            if used == chunk.count && buf.isEmpty { return used }
        }
        // After seeding, accumulate fixed tail (8 bytes)
        let need = 11 - buf.count
        if need > 0 {
            let take = min(need, chunk.count - used)
            if take > 0 { buf.append(chunk[used..<(used+take)]); used += take }
            if buf.count == 11 {
                // parse big-endian >HHI after \"BUF\"
                let w = UInt16(buf[3]) << 8 | UInt16(buf[4])
                let h = UInt16(buf[5]) << 8 | UInt16(buf[6])
                let c = UInt32(buf[7]) << 24 | UInt32(buf[8]) << 16 | UInt32(buf[9]) << 8 | UInt32(buf[10])
                width = Int(w); height = Int(h); count = Int(c)
                haveHeader = true
            }
        }
        // Any trailing bytes on this chunk remain (could be optional field or start of FR2).
        return used
    }
}

/// FR2 assembler (exactly one JPEG payload):
///   \"FR2\" + >H w + >H h + >I size + B pixfmt + >H frameID  (14 bytes)
final class FR2Assembler {
    private var finder = SigFinder("FR2")
    private var header = Data()
    private(set) var w = 0, h = 0, size = 0, pix: UInt8 = 0, fid = 0
    private var payload = Data()
    private(set) var done = false

    func reset() { finder = SigFinder("FR2"); header.removeAll(keepingCapacity: true); payload.removeAll(keepingCapacity: true); done = false }

    /// Returns bytes consumed; when done == true, call takeJPEG() to extract and then reset() to reuse.
    func consume(_ chunk: Data) -> Int {
        var used = 0
        if done { return 0 }

        // 1) header seek/build
        if header.count < 14 {
            if header.isEmpty {
                for b in chunk {
                    used += 1
                    if finder.feed(b) { header = Data([0x46,0x52,0x32]) /* FR2 */; break }
                }
                if header.isEmpty { return used }
            }
            let need = 14 - header.count
            let take = min(need, chunk.count - used)
            if take > 0 { header.append(chunk[used..<(used+take)]); used += take }
            if header.count == 14 {
                // parse >HHIBH (after \"FR2\")
                let wBE = UInt16(header[3]) << 8 | UInt16(header[4])
                let hBE = UInt16(header[5]) << 8 | UInt16(header[6])
                let sBE = (UInt32(header[7]) << 24) | (UInt32(header[8]) << 16) | (UInt32(header[9]) << 8) | UInt32(header[10])
                let pixf = header[11]
                let fidBE = UInt16(header[12]) << 8 | UInt16(header[13])
                w = Int(wBE); h = Int(hBE); size = Int(sBE); pix = pixf; fid = Int(fidBE)
                payload.reserveCapacity(size)
            }
        }

        // 2) payload
        if header.count == 14 && payload.count < size {
            let rem = size - payload.count
            let take = min(rem, chunk.count - used)
            if take > 0 { payload.append(chunk[used..<(used+take)]); used += take }
            if payload.count == size { done = true }
        }
        return used
    }

    func takeJPEG() -> Data? {
        guard done else { return nil }
        let out = payload
        reset()
        return out
    }
}
