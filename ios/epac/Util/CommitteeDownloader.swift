//
//  CommitteeDownloader.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-05-26.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation
import Kanna

class CommitteeDownloader {
    let hosturl: String = "https://www.ourcommons.ca"
    var listurl: String = "/Committees/<L>/List"
    var meetingsurl: String = "/Committees/<L>/<ABBR>/Meetings"

    var language: String
    var committeeList: [Committee]?
    var evidenceList: [String: [CommitteeEvidence]] = [:]

    init() {
        if Locale.current.identifier.contains("fr") {
            language = "F"
            listurl = listurl.replacingOccurrences(of: "<L>", with: "fr")
            meetingsurl = meetingsurl.replacingOccurrences(of: "<L>", with: "fr")
        } else {
            language = "E"
            listurl = listurl.replacingOccurrences(of: "<L>", with: "en")
            meetingsurl = meetingsurl.replacingOccurrences(of: "<L>", with: "en")
        }
    }

    func downloadEvidenceList(forCommittee acronym: String, completion: @escaping ([CommitteeEvidence]?) -> Void) {
        if let list = evidenceList[acronym] {
            Log.debug("Evidence list from memory")
            completion(list)
            return
        } else if FileManager.default.fileExists(atPath: File.documentDirectoryURL.appendingPathComponent("evidence", isDirectory: true).appendingPathComponent("\(acronym).list").path) {
            Log.debug("Evidence list from disk")
            let path = File.documentDirectoryURL.appendingPathComponent("evidence", isDirectory: true).appendingPathComponent("\(acronym).list").path
            // Legacy NSKeyedUnarchiver cache from cabinetdoor (2017); migration to
            // SwiftData persistence tracked in a separate cleanup ticket. The file we
            // wrote in this same path is known to be a [CommitteeEvidence] archive.
            // swiftlint:disable:next force_cast
            let list = NSKeyedUnarchiver.unarchiveObject(withFile: path) as! [CommitteeEvidence]
            completion(list)
            return
        } else {
            Log.debug("Evidence list from network")
            let meetingslink = meetingsurl.replacingOccurrences(of: "<ABBR>", with: acronym)
//            Alamofire.request(hosturl.appending(meetingslink)).responseString { response in
//                guard let htmlstring = response.result.value,
//                    let doc = HTML(html: htmlstring, url: nil, encoding: .utf8) else {
//                        completion(nil)
//                        return
//                }
//                var evidencelist: [CommitteeEvidence] = []
//                for item in doc.css("div.accordion-item") {
//                    guard let a_evidence = doc.at_css("a.btn-meeting-evidence"),
//                        let a_notice = doc.at_css("a.btn-meeting-notice"),
//                        let noticehref = a_notice["href"] else {
//                        continue
//                    }
//                    let noticeurl = "https:".appending(noticehref)
//                    let dateLabel = item.at_css("span.date-label.hidden-sm")!.text!
//                    let date = DateUtils.instance.getDate(forCommitteeMeetingDateString: dateLabel)
//                    var studyitem: String? = nil
//                    for studiesitem in item.css("div.studies-activities-item") {
//                        if let studytext = studiesitem.text,
//                            studytext.lowercased() != NSLocalizedString("committee business", comment: "") {
//                            studyitem = studytext
//                        }
//                    }
//                    let evidence = CommitteeEvidence(date: date, witnesses: [], studyitem: studyitem)
//                    evidencelist.append(evidence)
//                }
//                DispatchQueue.global(qos: .background).async {
//                    let path = File.documentDirectoryURL.appendingPathComponent("evidence", isDirectory: true).appendingPathComponent("\(acronym).list")
//                    let data = NSKeyedArchiver.archivedData(withRootObject: evidencelist)
//                    try? data.write(to: path)
//                }
//                completion(evidencelist)
//            }
        }
    }

    func downloadList(completion: @escaping ([Committee]?) -> Void) {
        if committeeList != nil {
            Log.debug("Committees from memory")
            completion(committeeList!)
            return
        } else if FileManager.default.fileExists(atPath: File.documentDirectoryURL.appendingPathComponent("committees.list").path) {
            Log.debug("Committees from disk")
            let path = File.documentDirectoryURL.appendingPathComponent("committees.list")
            // Legacy NSKeyedUnarchiver cache (see force_cast comment above).
            // swiftlint:disable:next force_cast
            let list = NSKeyedUnarchiver.unarchiveObject(withFile: path.path) as! [Committee]
            completion(list)
            return
        } else {
            Log.debug("Committees from network")
//            Alamofire.request(hosturl.appending(listurl)).responseString { response in
//                guard let htmlstring = response.result.value,
//                    let doc = HTML(html: htmlstring, url: nil, encoding: .utf8) else {
//                    completion(nil)
//                    return
//                }
//                var committees: [Committee] = []
//                for title in doc.css("div.accordion-bar-title") {
//                    let acronym = title.at_css("span.committee-acronym-cell")!.text!
//                    let name = title.at_css("span.committee-name")!.text!
//                    let committee = Committee(name: name, abbreviation: acronym)
//                    committees.append(committee)
//                }
//                DispatchQueue.global(qos: .background).async {
//                    let path = File.documentDirectoryURL.appendingPathComponent("committees.list")
//                    let data = NSKeyedArchiver.archivedData(withRootObject: committees)
//                    try? data.write(to: path)
//                }
//                completion(committees)
//                return
//            }
        }
    }
}
