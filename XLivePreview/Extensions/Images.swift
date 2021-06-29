//
//  Images.swift
//  XLivePreview
//
//  Created by Mihael Isaev on 16.06.2021.
//

import UIKitPlus

extension NSImage {
    static func statusIcon(_ color: NSColor) -> NSImage? {
        let image = NSImage(imageLiteralResourceName: "statusIcon")
        image.size = .init(width: 22, height: 22)
        return image.image(withTintColor: color)
    }
}
