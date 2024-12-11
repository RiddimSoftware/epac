//
//  Evidence.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-05-26.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation

class CommitteeEvidence : NSObject, NSCoding {
    
    var date: Date
    var witnesses: [Speaker]
    var studyitem: String?
    
    init(date: Date, witnesses: [Speaker], studyitem: String?) {
        self.date = date
        self.witnesses = witnesses
        self.studyitem = studyitem
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(date, forKey: "date")
        aCoder.encode(witnesses, forKey: "witnesses")
        aCoder.encode(studyitem, forKey: "studyitem")
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.witnesses = aDecoder.decodeObject(forKey: "witnesses") as! [Speaker]
        self.date = aDecoder.decodeObject(forKey: "date") as! Date
        self.studyitem = aDecoder.decodeObject(forKey: "studyitem") as? String
    }
}
