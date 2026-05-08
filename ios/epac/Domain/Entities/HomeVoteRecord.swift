//
//  HomeVoteRecord.swift
//  epac
//

import Foundation

struct HomeVoteRecord {
    let voteID: Int
    let number: Int
    let descriptionEn: String
    let billNumberCode: String
    let resultEn: String
    let date: Date
    let yea: Int
    let nay: Int
    let paired: Int
}

struct HomeMemberVoteRecord {
    let voteID: Int
    let memberID: Int
    let recordedVote: String  // "Yea", "Nay", "Paired", "Abstained"
}
