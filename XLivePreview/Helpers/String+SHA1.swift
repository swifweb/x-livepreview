//
//  HMAC.swift
//
//  Created by Mihael Isaev on 21.04.15.
//  Copyright (c) 2014 Mihael Isaev inc. All rights reserved.
//

import Foundation
import CommonCrypto

public extension String {
    var sha512: String { HMAC.hash(self) }
}

public extension Data {
    var sha512: String { HMAC.hash(self) }
}

public struct HMAC {
    static func hash(_ inp: String) -> String {
        if let stringData = inp.data(using: .utf8, allowLossyConversion: false) {
            return hash(stringData)
        }
        return ""
    }
    
    static func hash(_ inp: Data) -> String {
        hexStringFromData(_sha512(inp))
    }
    
    fileprivate static func _sha512(_ input : Data) -> Data {
        let digestLength = Int(CC_SHA512_DIGEST_LENGTH)
        var hash = [UInt8](repeating: 0, count: digestLength)
        CC_SHA512((input as NSData).bytes, UInt32(input.count), &hash)
        return Data(bytes: hash, count: digestLength)
    }
    
    fileprivate static func hexStringFromData(_ input: Data) -> String {
        var bytes = [UInt8](repeating: 0, count: input.count)
        (input as NSData).getBytes(&bytes, length: input.count)
        return bytes.map { String(format:"%02x", UInt8($0)) }.joined(separator: "")
    }
}
