//
//  Downloader.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-05-13.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation
import Kanna
import SWXMLHash

class Downloader {
    let hosturl: String = "https://www.ourcommons.ca";
    let calendarurl: String = "/en/sitting-calendar/";
    let dailyurl: String = "/en/parliamentary-business/";
    let xmlurl: NSString = "/Content/House/%@/Debates/%@/HAN%@-%@.XML";
    var language: String
    
    private var dateXMLString:      [Date:String] = [:]
    
    init() {
        if Locale.current.identifier.contains("fr") {
            language = "F"
        }
        else {
            language = "E"
        }
    }
    
    func downloadXML(forDate date: Date, completion: @escaping (String?)->()) {
        if let string = dateXMLString[date] {
            print("xml from memory")
            completion(string)
        }
        else if let string = UserDefaults.standard.string(forKey: "\(DateUtils.instance.getCSVStringFromDate(date))_\(Locale.current.identifier)_v2") {
            print("xml from disk")
            dateXMLString[date] = string
            completion(string)
        }
        else {
            print("xml from network")
            let datelink = hosturl.appending(dailyurl).appending(DateUtils.instance.getCSVStringFromDate(date))
//            Alamofire.request(datelink).responseString {
//                [weak self] response in
//                guard let `self` = self else {
//                    return
//                }
//                guard let htmlstring = response.result.value,
//                    let doc = HTML(html: htmlstring, url: nil, encoding: .utf8) else {
//                        completion(nil)
//                        return
//                }
//                var href: String?
//                for debatelink in doc.css("a.active-publication-link") {
//                    guard let text = debatelink.text?.lowercased() else {
//                        completion(nil)
//                        return
//                    }
//                    if text.contains("hansard") {
//                        href = debatelink["href"]
//                    }
//                    else if text.contains("projected") {
//                        completion(nil)
//                        return
//                    }
//                }
//                guard href != nil else {
//                    completion(nil)
//                    return
//                }
//                let pathcomponents = href!.components(separatedBy: "/")
//                guard pathcomponents.count == 7 else {
//                    completion(nil)
//                    return
//                }
//                let parlsession: String = pathcomponents[3].replacingOccurrences(of: "-", with: "")
//                let sittingcomponents = pathcomponents[5].components(separatedBy: "-")
//                guard sittingcomponents.count == 2 else {
//                    completion(nil)
//                    return
//                }
//                let sittingnumber = sittingcomponents[1]
//                let xmllinkpath: String = NSString(format: self.xmlurl,
//                                           parlsession,
//                                           sittingnumber,
//                                           sittingnumber,
//                                           self.language) as String
//                let xmllink: String = self.hosturl.appending(xmllinkpath)
//                Alamofire.request(xmllink).responseString { xmlresponse in
//                    guard let datavalue = xmlresponse.data,
//                        let utfstringvalue = String(data: datavalue, encoding: .utf8) else {
//                            completion(nil)
//                            return
//                    }
//                    UserDefaults.standard.set(utfstringvalue, forKey: "\(DateUtils.instance.getCSVStringFromDate(date))_\(Locale.current.identifier)_v2")
//                    self.dateXMLString[date] = utfstringvalue
//                    completion(utfstringvalue)
//                }
//            }
        }
    }
    
    func downloadCalendar(completion: @escaping ([Date])->()) {
        if let calendardates = UserDefaults.standard.value(forKey: "calendardates_v2") as? [Date] {
            completion(calendardates)
            return
        }
//        Alamofire.request(hosturl.appending(calendarurl)).responseString { response in
//            if let htmlstring = response.result.value,
//                let doc = HTML(html: htmlstring, url: nil, encoding: String.Encoding.utf8) {
//                var dates: [Date] = []
//                for cssdate in doc.css("td.chamber-meeting") {
//                    guard let attrclass = cssdate["class"],
//                        attrclass.contains("chamber-meeting") else {
//                        continue
//                    }
//                    let classes = attrclass.components(separatedBy: " ")
//                    guard let datestring = classes.first else {
//                        continue
//                    }
//                    let date = DateUtils.instance.getDate(forCSVDateString: datestring)
//                    dates.append(date)
//                }
//                dates.sort { d1,d2 -> Bool in
//                    d1.timeIntervalSince(d2) >= 0
//                }
//                UserDefaults.standard.set(dates, forKey: "calendardates_v2")
//                completion(dates)
//            }
//        }
    }

}
