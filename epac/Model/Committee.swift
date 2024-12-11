//
//  Committee.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-05-26.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation

class Committee : NSObject, NSCoding {
    
    var abbreviation: String
    var name: String
    
    init(name: String, abbreviation: String) {
        self.name = name
        self.abbreviation = abbreviation
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(abbreviation, forKey: "abbreviation")
        aCoder.encode(name, forKey: "name")
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.abbreviation = aDecoder.decodeObject(forKey: "abbreviation") as! String
        self.name = aDecoder.decodeObject(forKey: "name") as! String
    }
}
