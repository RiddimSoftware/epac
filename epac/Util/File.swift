//
//  File.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-05-26.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation

class File {
    
    static let documentDirectoryURL =  try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
}
