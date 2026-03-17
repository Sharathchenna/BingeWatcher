//
//  Item.swift
//  BingeWatcher
//
//  Created by Sharath Chenna on 18/03/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
