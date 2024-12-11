//
//  Debate.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-06.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation

typealias MessageSpeaker = (Speaker?, Speaker?)

class Debate {
    
    private var speeches:       [Speech]
    private var speakers:       [Speaker]
    private var iterator:       IndexingIterator<[Speech]>
    private var model:          Model = Model.instance
    private var currentSpeech:  Speech?
    
    var messages:       [DebateSpeechMessage]
    var lastMessage:    DebateSpeechMessage?
    var subtopic:       Topic
    var date:           Date
    var length:         Int = 0
    var subject:        SubjectOfBusiness
    
    init(date: Date, subject: SubjectOfBusiness) {
        self.date = date
        self.subtopic = Topic(name: subject.title)
        self.speeches = subject.speeches
        iterator = self.speeches.makeIterator()
        self.messages = []
        self.currentSpeech = iterator.next()
        self.speakers = []
        var speaker: Speaker? = nil
        for speech in speeches {
            speech.reset()
            self.length += speech.length
            if speaker == speech.speaker {
                continue
            }
            else {
                speaker = speech.speaker
                self.speakers.append(speaker!)
            }
        }
        self.subject = subject
    }
    
    func reset() {
        iterator = self.speeches.makeIterator()
        messages.removeAll()
    }
    
    func speak(andNotify shouldNotify: Bool = true) -> Bool {
        if let speech = currentSpeech {
            let canContinue = speech.speak()
            if canContinue == false {
                currentSpeech = iterator.next()
            }
            if let lastMessage = speech.lastMessage {
                var messagespeaker: MessageSpeaker = (nil, nil)
                if speakers.index(of: lastMessage.speaker)! % 2 == 0 {
                    messagespeaker.0 = lastMessage.speaker
                }
                else {
                    messagespeaker.1 = lastMessage.speaker
                }
                self.lastMessage = DebateSpeechMessage(speechmessage: lastMessage, messagespeaker: messagespeaker)
                messages.append(self.lastMessage!)
            }
            if shouldNotify {
                NotificationCenter.default.post(name: Debate.speaknotification, object: self)
            }
        }
        return currentSpeech != nil
    }
}

extension Debate: Hashable, Equatable {
    var hashValue: Int {
        return subject.hashValue
    }
    static func ==(lhs: Debate, rhs: Debate) -> Bool {
        return lhs.subject == rhs.subject
    }
    static let speaknotification: Notification.Name = Notification.Name(rawValue: "speaknotification")
}

class DebateSpeechMessage: SpeechMessage {
    var messagespeaker: MessageSpeaker!
    private var currentSpeaker: Speaker
    convenience init(speechmessage: SpeechMessage, messagespeaker: MessageSpeaker) {
        self.init(text: speechmessage.text(), speaker: messagespeaker.0 ?? messagespeaker.1!)
        self.messagespeaker = messagespeaker
    }
    override init(text: String, speaker: Speaker) {
        self.currentSpeaker = speaker
        super.init(text: text, speaker: speaker)
    }
    override func senderId() -> String {
        return messagespeaker.0 == nil ? "0" : messagespeaker.0!.name
    }
    override func senderDisplayName() -> String {
        return self.currentSpeaker.name
    }
    override var speaker: Speaker {
        get {
            return currentSpeaker
        }
        set {
            
        }
    }
}
