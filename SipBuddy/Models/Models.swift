import Foundation
import SwiftUI

// MARK: - Water entry

struct WaterEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var amountML: Int
    var date: Date
}

// MARK: - Units

enum VolumeUnit: String, Codable, CaseIterable, Identifiable {
    case milliliters, liters, ounces

    var id: String { rawValue }
    static let mlPerOunce = 29.5735

    var label: String {
        switch self {
        case .milliliters: return "Millilitres (ml)"
        case .liters: return "Litres (L)"
        case .ounces: return "Fluid ounces (oz)"
        }
    }

    var symbol: String {
        switch self {
        case .milliliters: return "ml"
        case .liters: return "L"
        case .ounces: return "oz"
        }
    }

    func value(fromML ml: Int) -> Double {
        switch self {
        case .milliliters: return Double(ml)
        case .liters: return Double(ml) / 1000
        case .ounces: return Double(ml) / Self.mlPerOunce
        }
    }

    func ml(from value: Double) -> Int {
        switch self {
        case .milliliters: return Int(value.rounded())
        case .liters: return Int((value * 1000).rounded())
        case .ounces: return Int((value * Self.mlPerOunce).rounded())
        }
    }

    func format(_ ml: Int, symbol showSymbol: Bool = true) -> String {
        let v = value(fromML: ml)
        let number: String
        switch self {
        case .milliliters: number = Int(v).formatted()
        case .liters: number = v.formatted(.number.precision(.fractionLength(0...2)))
        case .ounces: number = v.formatted(.number.precision(.fractionLength(0...1)))
        }
        return showSymbol ? "\(number) \(symbol)" : number
    }
}

// MARK: - Personality & messages

enum Personality: String, Codable, CaseIterable, Identifiable {
    case friendlyFriend, funnyBuddy, motivationalCoach, minimalAssistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .friendlyFriend: return "Friendly Friend"
        case .funnyBuddy: return "Funny Buddy"
        case .motivationalCoach: return "Motivational Coach"
        case .minimalAssistant: return "Minimal Assistant"
        }
    }

    var subtitle: String {
        switch self {
        case .friendlyFriend: return "Casual and caring"
        case .funnyBuddy: return "Playful and humorous"
        case .motivationalCoach: return "Positive and energetic"
        case .minimalAssistant: return "Short and professional"
        }
    }

    var symbol: String {
        switch self {
        case .friendlyFriend: return "face.smiling"
        case .funnyBuddy: return "theatermasks"
        case .motivationalCoach: return "figure.run"
        case .minimalAssistant: return "text.alignleft"
        }
    }
}

enum MessageCategory: String, CaseIterable {
    case friendly, funny, motivational, caring, workBreak, goal, minimal
}

// MARK: - Reminder presentation

enum ReminderStyle: String, Codable, CaseIterable, Identifiable {
    case fullScreen, gestureCard, notification
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fullScreen: return "Full screen — closes when you drink"
        case .gestureCard: return "Corner card — closes when you drink"
        case .notification: return "Standard macOS notification"
        }
    }
    /// Shown by SipBuddy itself and closed when the camera sees you drinking.
    var usesGesture: Bool { self != .notification }
}

// MARK: - Appearance

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum AccentChoice: String, Codable, CaseIterable, Identifiable {
    case ocean, aqua, teal, indigo, mint, coral
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .ocean: return Color(red: 0.16, green: 0.50, blue: 0.96)
        case .aqua: return Color(red: 0.10, green: 0.70, blue: 0.86)
        case .teal: return Color(red: 0.10, green: 0.62, blue: 0.62)
        case .indigo: return Color(red: 0.38, green: 0.40, blue: 0.94)
        case .mint: return Color(red: 0.20, green: 0.74, blue: 0.56)
        case .coral: return Color(red: 0.96, green: 0.45, blue: 0.42)
        }
    }
}

// MARK: - Pause options

enum PauseOption: CaseIterable, Identifiable {
    case thirtyMinutes, oneHour, twoHours, fourHours, restOfToday, untilResumed
    var id: Self { self }

    var label: String {
        switch self {
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        case .restOfToday: return "Rest of today"
        case .untilResumed: return "Until I resume"
        }
    }

    func endDate(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .thirtyMinutes: return now.addingTimeInterval(30 * 60)
        case .oneHour: return now.addingTimeInterval(3600)
        case .twoHours: return now.addingTimeInterval(2 * 3600)
        case .fourHours: return now.addingTimeInterval(4 * 3600)
        case .restOfToday:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        case .untilResumed: return .distantFuture
        }
    }
}

// MARK: - Helpers

extension Date {
    /// Minutes since midnight in the given calendar.
    func minutesOfDay(_ calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: self)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Today's date at the given minutes after midnight (used by time pickers).
    static func today(atMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }
}

extension Int {
    var asClockString: String {
        Date.today(atMinutes: self).formatted(date: .omitted, time: .shortened)
    }
}
