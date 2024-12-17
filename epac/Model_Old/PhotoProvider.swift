//
//  PhotoProvider.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-05.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation

class PhotoProvider {

	//    static var instance = PhotoProvider()
	//    private static let hostURL: String = "http://www.parl.gc.ca/Parliamentarians/Images/OfficialMPPhotos/42"
	private static let hostURL: URL = URL(string: "https://www.ourcommons.ca/Content/Parliamentarians/Images/OfficialMPPhotos/44")!

	static func getPhotoURL(lastName: String, firstName: String, party: Party) -> URL {

		let url = hostURL.appending(
			path: "\(lastName.replacing(/\P{L}/, with: ""))\(firstName.replacing(/\P{L}/, with: ""))_\(party.abbreviation).jpg".replacingOccurrences(of: "ç", with: "c")
		)
		return url

		//        let unicodestring = "\(hostURL)/\(lastName)\(firstName)_\(partyAbbreviation).jpg"
		//        return unicodestring.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)!
	}
}

//protocol AvatarProviderDelegate {
//    func avatarProviderDidDownloadImage(_ provider: AvatarProvider)
//}

//class AvatarProvider: NSObject, JSQMessageAvatarImageDataSource {
//    private let avatarFont: UIFont = UIFont(name: "CooperHewitt-Bold", size: 12)!
//    private var avatarFactory: JSQMessagesAvatarImageFactory = JSQMessagesAvatarImageFactory(diameter: 47)
//    private var _avatarImage: UIImage?
//    private var _placeholderImage: UIImage!
//    private var speaker: Speaker
//    private var model: Model = Model.instance
//
//    var delegate: AvatarProviderDelegate?
//
//    init(speaker: Speaker) {
//        self.speaker = speaker
//        super.init()
//        let size = CGSize(width: 47, height: 77)
//        UIGraphicsBeginImageContext(size)
//        let context = UIGraphicsGetCurrentContext()
//        let rect = CGRect(origin: CGPoint.zero, size: size)
//        context!.setFillColor(UIColor.white.cgColor)
//        context!.addRect(rect)
//        context!.fill(rect)
//        _placeholderImage = UIGraphicsGetImageFromCurrentImageContext()
//        UIGraphicsEndImageContext()
//        if let image = model.speakerImages[speaker] {
//            _avatarImage = image
//        }
//        else if let url = speaker.photoURL {
//            let request = URLRequest(url: url)
//            ImageDownloader.default.download(request, completion: { [weak self] response in
//                if let data = response.data {
//                    self?._avatarImage = UIImage(data: data)
//                    if let `self` = self {
//                        self.model.speakerImages[speaker] = self._avatarImage
//                        self.delegate?.avatarProviderDidDownloadImage(self)
//                    }
//                }
//            })
//        }
//    }
//
//    func avatarPlaceholderImage() -> UIImage {
//        if _placeholderImage == nil {
//        }
//        return _placeholderImage
//    }
//
//    func avatarImage() -> UIImage? {
//        return _avatarImage
//    }
//
//    func avatarHighlightedImage() -> UIImage? {
//        return nil
//    }
//}
