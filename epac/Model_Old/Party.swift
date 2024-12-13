//
//  Party.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-05.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation
import UIKit

enum Party {
    case conservative
    case liberal
    case newdemocratic
    case bloc
    case green
    case other
    
    var abbreviation: String {
        switch self {
        case .conservative:     return "CPC"
        case .liberal:          return "Lib"
        case .newdemocratic:    return "NDP"
        case .bloc:             return "BQ"
        case .green:            return "GP"
        case .other:            return ""
        }
    }
    
    var localizedAbbreviation: String {
        switch self {
        case .conservative:     return NSLocalizedString("CPC", comment: "")
        case .liberal:          return NSLocalizedString("Lib", comment: "")
        case .newdemocratic:    return NSLocalizedString("NDP", comment: "")
        case .bloc:             return NSLocalizedString("BQ", comment: "")
        case .green:            return NSLocalizedString("GP", comment: "")
        case .other:            return ""
        }
    }
    
    var fullName: String {
        switch self {
        case .conservative:     return NSLocalizedString("Conservative", comment: "")
        case .liberal:          return NSLocalizedString("Liberal", comment: "")
        case .newdemocratic:    return NSLocalizedString("New Democratic Party", comment: "")
        case .bloc:             return NSLocalizedString("Bloc Québécois", comment: "")
        case .green:            return NSLocalizedString("Green Party", comment: "")
        case .other:            return ""
        }
    }
    
    var colour: UIColor {
        switch self {
        case .conservative:     return UIColor(rgb: 0x1A4782)
        case .liberal:          return UIColor(rgb: 0xd71920)
        case .newdemocratic:    return UIColor(rgb: 0xF37021)
        case .bloc:             return UIColor(rgb: 0x33B2CC)
        case .green:            return UIColor(rgb: 0x3D9B35)
        case .other:            return UIColor.darkText
        }
    }
    
    static func partyWithAbbreviation(_ name: String) -> Party {
        if name == Party.conservative.localizedAbbreviation {
            return .conservative
        } else if name == Party.liberal.localizedAbbreviation {
            return .liberal
        } else if name == Party.newdemocratic.localizedAbbreviation {
            return .newdemocratic
        } else if name == Party.bloc.localizedAbbreviation {
            return .bloc
        } else if name == Party.green.localizedAbbreviation {
            return .green
        }
        return .other
    }
}
