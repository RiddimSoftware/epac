//
//  ActivityItemSource.swift
//  epac
//

import LinkPresentation
import UIKit

class ShareActivityItemSource: NSObject, UIActivityItemSource {
    let image: UIImage
    let title: String
    let url: URL?

    init(image: UIImage, title: String, url: URL? = nil) {
        self.image = image
        self.title = title
        self.url = url
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return image
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return image
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        
        // Provide the bottom-leading square of the image for the preview thumbnail
        let previewImage = image.bottomLeadingSquare() ?? image
        metadata.imageProvider = NSItemProvider(object: previewImage)
        
        if let url = url {
            metadata.url = url
            metadata.originalURL = url
        }
        return metadata
    }
}

extension UIImage {
    func bottomLeadingSquare() -> UIImage? {
        let side = min(size.width, size.height)
        
        // Use pixels for CGImage cropping
        let x = 0.0
        let y = (size.height - side) * scale
        let width = side * scale
        let height = side * scale
        
        let cropRect = CGRect(x: x, y: y, width: width, height: height)
        
        guard let cgImage = self.cgImage?.cropping(to: cropRect) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
}
