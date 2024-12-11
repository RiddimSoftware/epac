//
//  Topic.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-07.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation

class Topic: NSCoding, Hashable, Equatable {
    
    var name: String
    var id: String
    var speechcount: Int = 0
    
    init(name: String) {
        self.name = name
        self.id = name
    }
    
    required init?(coder aDecoder: NSCoder) {
        guard let name = aDecoder.decodeObject(forKey: "name") as? String else {
            return nil
        }
        self.name = name
        self.speechcount = aDecoder.decodeInteger(forKey: "speechcount")
        self.id = name
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(name, forKey: "name")
        aCoder.encode(speechcount, forKey: "speechcount")
    }
    
    var hashValue: Int {
        return name.hashValue
    }
    
    static func ==(lhs: Topic, rhs: Topic) -> Bool {
        return lhs.name == rhs.name
    }
}
