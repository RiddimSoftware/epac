//
//  Speech.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-04.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation
import SWXMLHash

class Speech: CustomDebugStringConvertible {
    private var _messages:      [SpeechMessage]
    private var index:          Int = 0
    private(set) var content:   [String]
    
    var speaker:        Speaker
    var messages:       [SpeechMessage]
    var lastMessage:    SpeechMessage?
    var date:           Date
    var length:         Int
    var title:          String
    var id:             String
    
    init(paragraphXML: XMLIndexer, speaker: Speaker, title: String, id: String) {
        self._messages = []
        self.messages = []
        self.date = Date()
        self.id = id
        self.lastMessage = nil
        self.speaker = speaker
        content = []
        for p in content {
            self._messages.append(SpeechMessage(text: p, speaker: self.speaker))
        }
        self.length = self._messages.count
        self.title = title
    }
    
    init(id: String, speaker: Speaker, content: [String], date: Date, maintopic: String = "", subtopic: Topic = Topic(name: ""), subsubtopic: String? = nil) {
        self.content = content
        self.speaker = speaker
        self._messages = []
        for p in content {
            self._messages.append(SpeechMessage(text: p, speaker: speaker))
        }
        self.length = self._messages.count
        self.messages = []
        self.date = date
        self.id = id
        self.lastMessage = nil
        self.title = maintopic
    }
    
    func reset() {
        index = 0
        messages.removeAll()
    }
    
    func speak() -> Bool {
        if index < _messages.count {
            lastMessage = _messages[index]
            self.messages.append(lastMessage!)
            index += 1
            return index < _messages.count
        }
        return false
    }
    
    var debugDescription: String {
        return "Speech:\(content)\n"
    }
}

class SpeechMessage: NSObject {
    private var content:    String
    private var timestamp:  Date
    
    var speaker:    Speaker
    
    init(text: String, speaker: Speaker) {
        self.content = text
        self.speaker = speaker
        self.timestamp = Date()
    }
    func senderId() -> String {
        return speaker.name
    }
    func senderDisplayName() -> String {
        return speaker.name
    }
    func date() -> Date {
        return timestamp
    }
    func isMediaMessage() -> Bool {
        return false
    }
    func messageHash() -> UInt {
        return UInt(abs(content.hash))
    }
    override var hash: Int {
        return content.hash
    }
    func text() -> String {
        return content
    }
}
