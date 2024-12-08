//
//  Item.swift
//  epac
//
//  Created by Sunny on 2024-12-08.
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
