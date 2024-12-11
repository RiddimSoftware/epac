//
//  CommitteeModel.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-05-26.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation

class CommitteeModel {
    
    static let instance = CommitteeModel()
    let downloader: CommitteeDownloader = CommitteeDownloader()
    
    func getCommittees(completion: @escaping ([Committee]?)->()) {
        downloader.downloadList(completion: completion)
    }
    
    func getEvidenceList(forCommittee acronym: String, completion: @escaping ([CommitteeEvidence]?)->()) {
        downloader.downloadEvidenceList(forCommittee: acronym, completion: completion)
    }
}
