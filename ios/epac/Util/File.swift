//
//  File.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-05-26.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation

class File {

    // FileManager.default.url(for: .documentDirectory, ...) is documented to never throw
    // for the user-domain documents directory on iOS — the only failure modes are sandbox
    // misconfiguration. SwiftLint baseline accepts the force-try here.
    // swiftlint:disable:next force_try
    static let documentDirectoryURL =  try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
}
