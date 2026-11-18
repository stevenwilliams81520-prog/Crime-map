import UIKit
import SwiftUI

// MARK: - Crime types

enum CrimeType: String, CaseIterable, Identifiable {
    case violentCrime = "violent-crime"
    case robbery = "robbery"
    case possessionOfWeapons = "possession-of-weapons"
    case burglary = "burglary"
    case vehicleCrime = "vehicle-crime"
    case theftFromThePerson = "theft-from-the-person"
    case otherTheft = "other-theft"
    case shoplifting = "shoplifting"
    case bicycleTheft = "bicycle-theft"
    case criminalDamageArson = "criminal-damage-arson"
    case publicOrder = "public-order"
    case antiSocialBehaviour = "anti-social-behaviour"
    case drugs = "drugs"
    case otherCrime = "other-crime"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .violentCrime: return "Violence & sexual offences"
        case .robbery: return "Robbery"
        case .possessionOfWeapons: return "Possession of weapons"
        case .burglary: return "Burglary"
        case .vehicleCrime: return "Vehicle crime"
        case .theftFromThePerson: return "Theft from the person"
        case .otherTheft: return "Other theft"
        case .shoplifting: return "Shoplifting"
        case .bicycleTheft: return "Bicycle theft"
        case .criminalDamageArson: return "Criminal damage & arson"
        case .publicOrder: return "Public order"
        case .antiSocialBehaviour: return "Anti-social behaviour"
        case .drugs: return "Drugs"
        case .otherCrime: return "Other crime"
        }
    }

    var hex: UInt32 {
        switch self {
        case .violentCrime: return 0xE5484D
        case .robbery: return 0xFF7B2E
        case .possessionOfWeapons: return 0xC2185B
        case .burglary: return 0xF5A524
        case .vehicleCrime: return 0x3E9BFF
        case .theftFromThePerson: return 0xA26BFF
        case .otherTheft: return 0x7C8CFF
        case .shoplifting: return 0x2FB7A5
        case .bicycleTheft: return 0x5EC26A
        case .criminalDamageArson: return 0xFF5C8A
        case .publicOrder: return 0xE6D34A
        case .antiSocialBehaviour: return 0x8A94A3
        case .drugs: return 0x9BE15D
        case .otherCrime: return 0xB0A18F
        }
    }

    var uiColor: UIColor { UIColor(hex: hex) }
}

struct CrimeGroup: Identifiable {
    let title: String
    let types: [CrimeType]
    var id: String { title }
}

let crimeGroups: [CrimeGroup] = [
    CrimeGroup(title: "Violence & weapons", types: [.violentCrime, .robbery, .possessionOfWeapons]),
    CrimeGroup(title: "Theft", types: [.burglary, .vehicleCrime, .theftFromThePerson, .otherTheft, .shoplifting, .bicycleTheft]),
    CrimeGroup(title: "Damage & disorder", types: [.criminalDamageArson, .publicOrder, .antiSocialBehaviour]),
    CrimeGroup(title: "Drugs & other", types: [.drugs, .otherCrime])
]

func crimeName(_ category: String) -> String {
    CrimeType(rawValue: category)?.name ?? category.replacingOccurrences(of: "-", with: " ").capitalized
}

func crimeColor(_ category: String) -> UIColor {
    CrimeType(rawValue: category)?.uiColor ?? .lightGray
}

// MARK: - Crime record

struct Crime: Identifiable, Hashable {
    let id = UUID()
    let category: String
    let street: String
    let month: String
    let outcome: String?
    let latitude: Double
    let longitude: Double
}

struct CrimeList: Identifiable {
    let id = UUID()
    let crimes: [Crime]
}

// MARK: - Helpers

private let monthIn: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.dateFormat = "yyyy-MM"
    return f
}()

private let monthOut: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.dateFormat = "MMMM yyyy"
    return f
}()

let allDates = "all"

func monthLabel(_ month: String) -> String {
    if month == allDates { return "All dates" }
    guard let d = monthIn.date(from: month) else { return month }
    return monthOut.string(from: d)
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    static let brand = Color(uiColor: UIColor(hex: 0xE5484D))
    static let panel = Color(uiColor: UIColor(hex: 0x1B2027))
    static let field = Color(uiColor: UIColor(hex: 0x151A20))
    static let line = Color(uiColor: UIColor(hex: 0x2C333D))
}
