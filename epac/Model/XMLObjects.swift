//
//  XMLObjects.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-15.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation
import SWXMLHash


class OrderOfBusiness : Hashable {
    var catchline: String
    var subjectsofbusiness: [SubjectOfBusiness]
    
    init(catchline: String) {
        self.catchline = catchline
        subjectsofbusiness = []
    }
    
    var hashValue: Int {
        return catchline.hashValue
    }
    
    static func ==(lhs: OrderOfBusiness, rhs: OrderOfBusiness) -> Bool {
        return lhs.catchline == rhs.catchline
    }
}

class SubjectOfBusiness : Hashable {
    var title: String
    var speeches: [Speech]
    var id: String
    
    init(title: String, id: String) {
        self.title = title.trimmingCharacters(in: CharacterSet.whitespaces)
        self.id = id
        speeches = []
    }
    
    var hashValue: Int {
        return id.hashValue
    }
    
    static func ==(lhs: SubjectOfBusiness, rhs:SubjectOfBusiness) -> Bool {
        return lhs.id == rhs.id
    }
}
