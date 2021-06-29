//
//  String+Random.swift
//
//  Created by Mihael Isaev on 22.05.2018.
//  Copyright © 2018 Mihael Isaev inc. All rights reserved.
//

import Foundation

extension String {
    public static func shuffledAlphabet(_ length: Int) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        var randomString = ""
        for _ in 0...length-1 {
            let rand = arc4random() % UInt32(letters.count)
            let ind = Int(rand)
            randomString.append(letters[ind])
        }
        return randomString
    }
}

private extension StringProtocol {
    subscript(offset: Int) -> Character {
        self[index(startIndex, offsetBy: offset)]
    }
}
