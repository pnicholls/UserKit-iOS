//
//  String+MD5.swift
//  Kingfisher
//
// To date, adding CommonCrypto to a Swift framework is problematic. See:
// http://stackoverflow.com/questions/25248598/importing-commoncrypto-in-a-swift-framework
// We're using a subset and modified version of CryptoSwift as an alternative.
// The following is an altered source version that only includes MD5. The original software can be found at:
// https://github.com/krzyzanowskim/CryptoSwift
// This is the original copyright notice:
/*
  Copyright (C) 2014 Marcin Krzyżanowski <marcin.krzyzanowski@gmail.com>
  This software is provided 'as-is', without any express or implied warranty.
  In no event will the authors be held liable for any damages arising from the use of this software.
  Permission is granted to anyone to use this software for any purpose,including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:
  - The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation is required.
  - Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
  - This notice may not be removed or altered from any source or binary distribution.
*/

import Foundation

extension String {
    var md5: String {
        if let data = self.data(using: .utf8, allowLossyConversion: true) {
            let message = data.withUnsafeBytes { bufferPointer -> [UInt8] in
                return Array(bufferPointer)
            }

            let MD5Calculator = MD5(message)
            let MD5Data = MD5Calculator.calculate()

            let MD5String = NSMutableString()
            for number in MD5Data {
                MD5String.appendFormat("%02x", number)
            }
            return MD5String as String
        } else {
            return self
        }
    }
}

/// array of bytes, little-endian representation
func arrayOfBytes<T>(_ value: T, length: Int? = nil) -> [UInt8] {
    let totalBytes = length ?? (MemoryLayout<T>.size * 8)

    let valuePointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
    valuePointer.pointee = value

    let bytes = valuePointer.withMemoryRebound(
        to: UInt8.self, capacity: totalBytes
    ) { bytesPointer -> [UInt8] in
        var bytes = [UInt8](repeating: 0, count: totalBytes)
        for byteLocation in 0..<min(MemoryLayout<T>.size, totalBytes) {
            bytes[totalBytes - 1 - byteLocation] =
                (bytesPointer + byteLocation).pointee
        }
        return bytes
    }

    valuePointer.deinitialize(count: 1)
    valuePointer.deallocate()

    return bytes
}

extension Int {
    /** Array of bytes with optional padding (little-endian) */
    func bytes(_ totalBytes: Int = MemoryLayout<Int>.size) -> [UInt8] {
        return arrayOfBytes(self, length: totalBytes)
    }
}

extension NSMutableData {
    /** Convenient way to append bytes */
    func appendBytes(_ arrayOfBytes: [UInt8]) {
        append(arrayOfBytes, length: arrayOfBytes.count)
    }
}

protocol HashProtocol {
    var message: [UInt8] { get }

    /** Common part for hash calculation. Prepare header data. */
    func prepare(_ len: Int) -> [UInt8]
}

extension HashProtocol {
    func prepare(_ len: Int) -> [UInt8] {
        var tmpMessage = message

        // Step 1. Append Padding Bits
        tmpMessage.append(0x80)  // append one bit (UInt8 with one bit) to message

        // append "0" bit until message length in bits ≡ 448 (mod 512)
        var msgLength = tmpMessage.count
        var counter = 0

        while msgLength % len != (len - 8) {
            counter += 1
            msgLength += 1
        }

        tmpMessage += [UInt8](repeating: 0, count: counter)
        return tmpMessage
    }
}

func toUInt32Array(_ slice: ArraySlice<UInt8>) -> [UInt32] {
    var result: [UInt32] = []
    result.reserveCapacity(16)

    for idx in stride(
        from: slice.startIndex, to: slice.endIndex,
        by: MemoryLayout<UInt32>.size)
    {
        let first = UInt32(slice[idx.advanced(by: 3)]) << 24
        let second = UInt32(slice[idx.advanced(by: 2)]) << 16
        let third = UInt32(slice[idx.advanced(by: 1)]) << 8
        let fourth = UInt32(slice[idx])
        let val: UInt32 = first | second | third | fourth

        result.append(val)
    }
    return result
}

struct BytesIterator: IteratorProtocol {
    let chunkSize: Int
    let data: [UInt8]

    init(chunkSize: Int, data: [UInt8]) {
        self.chunkSize = chunkSize
        self.data = data
    }

    var offset = 0

    mutating func next() -> ArraySlice<UInt8>? {
        let end = min(chunkSize, data.count - offset)
        let result = data[offset..<offset + end]
        offset += result.count
        return result.isEmpty ? nil : result
    }
}

struct BytesSequence: Sequence {
    let chunkSize: Int
    let data: [UInt8]

    func makeIterator() -> BytesIterator {
        return BytesIterator(chunkSize: chunkSize, data: data)
    }
}

func rotateLeft(_ value: UInt32, bits: UInt32) -> UInt32 {
    return ((value << bits) & 0xFFFF_FFFF) | (value >> (32 - bits))
}

class MD5: HashProtocol {
    static let size = 16  // 128 / 8
    let message: [UInt8]

    init(_ message: [UInt8]) {
        self.message = message
    }

    /** specifies the per-round shift amounts */
    private let shifts: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ]

    /** binary integer part of the sines of integers (Radians) */
    private let sines: [UInt32] = [
        0xd76a_a478, 0xe8c7_b756, 0x2420_70db, 0xc1bd_ceee,
        0xf57c_0faf, 0x4787_c62a, 0xa830_4613, 0xfd46_9501,
        0x6980_98d8, 0x8b44_f7af, 0xffff_5bb1, 0x895c_d7be,
        0x6b90_1122, 0xfd98_7193, 0xa679_438e, 0x49b4_0821,
        0xf61e_2562, 0xc040_b340, 0x265e_5a51, 0xe9b6_c7aa,
        0xd62f_105d, 0x0244_1453, 0xd8a1_e681, 0xe7d3_fbc8,
        0x21e1_cde6, 0xc337_07d6, 0xf4d5_0d87, 0x455a_14ed,
        0xa9e3_e905, 0xfcef_a3f8, 0x676f_02d9, 0x8d2a_4c8a,
        0xfffa_3942, 0x8771_f681, 0x6d9d_6122, 0xfde5_380c,
        0xa4be_ea44, 0x4bde_cfa9, 0xf6bb_4b60, 0xbebf_bc70,
        0x289b_7ec6, 0xeaa1_27fa, 0xd4ef_3085, 0x4881d05,
        0xd9d4_d039, 0xe6db_99e5, 0x1fa2_7cf8, 0xc4ac_5665,
        0xf429_2244, 0x432a_ff97, 0xab94_23a7, 0xfc93_a039,
        0x655b_59c3, 0x8f0c_cc92, 0xffef_f47d, 0x8584_5dd1,
        0x6fa8_7e4f, 0xfe2c_e6e0, 0xa301_4314, 0x4e08_11a1,
        0xf753_7e82, 0xbd3a_f235, 0x2ad7_d2bb, 0xeb86_d391,
    ]

    private let hashes: [UInt32] = [
        0x6745_2301, 0xefcd_ab89, 0x98ba_dcfe, 0x1032_5476,
    ]

    func calculate() -> [UInt8] {
        var tmpMessage = prepare(64)
        tmpMessage.reserveCapacity(tmpMessage.count + 4)

        // hash values
        var hashes = hashes

        // Step 2. Append Length a 64-bit representation of lengthInBits
        let lengthInBits = (message.count * 8)
        let lengthBytes = lengthInBits.bytes(64 / 8)
        tmpMessage += lengthBytes.reversed()

        // Process the message in successive 512-bit chunks:
        let chunkSizeBytes = 512 / 8  // 64

        for chunk in BytesSequence(chunkSize: chunkSizeBytes, data: tmpMessage)
        {
            // break chunk into sixteen 32-bit words M[j], 0 ≤ j ≤ 15
            let chunk = toUInt32Array(chunk)
            assert(chunk.count == 16, "Invalid array")

            // Initialize hash value for this chunk:
            var hashA: UInt32 = hashes[0]
            var hashB: UInt32 = hashes[1]
            var hashC: UInt32 = hashes[2]
            var hashD: UInt32 = hashes[3]

            var dTemp: UInt32 = 0

            // Main loop
            for sine in 0..<sines.count {
                var hashG = 0
                var hashF: UInt32 = 0

                switch sine {
                case 0...15:
                    hashF = (hashB & hashC) | ((~hashB) & hashD)
                    hashG = sine
                case 16...31:
                    hashF = (hashD & hashB) | (~hashD & hashC)
                    hashG = (5 * sine + 1) % 16
                case 32...47:
                    hashF = hashB ^ hashC ^ hashD
                    hashG = (3 * sine + 5) % 16
                case 48...63:
                    hashF = hashC ^ (hashB | (~hashD))
                    hashG = (7 * sine) % 16
                default:
                    break
                }
                dTemp = hashD
                hashD = hashC
                hashC = hashB
                hashB =
                    hashB
                    &+ rotateLeft(
                        (hashA &+ hashF &+ sines[sine] &+ chunk[hashG]),
                        bits: shifts[sine])
                hashA = dTemp
            }

            hashes[0] = hashes[0] &+ hashA
            hashes[1] = hashes[1] &+ hashB
            hashes[2] = hashes[2] &+ hashC
            hashes[3] = hashes[3] &+ hashD
        }

        var result: [UInt8] = []
        result.reserveCapacity(hashes.count / 4)

        hashes.forEach {
            let itemLE = $0.littleEndian
            result += [
                UInt8(itemLE & 0xff),
                UInt8((itemLE >> 8) & 0xff),
                UInt8((itemLE >> 16) & 0xff),
                UInt8((itemLE >> 24) & 0xff),
            ]
        }
        return result
    }
}
