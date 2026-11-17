import Foundation

struct ReminderMessage: Hashable {
    let id: Int
    let category: MessageCategory
    let template: String
}

struct MessageContext {
    var consumed: String
    var remaining: String
    var progress: Double
}

/// 70 conversational reminders, picked by personality, never repeating back to back.
final class MessageLibrary {
    private let defaults: UserDefaults
    private(set) var lastMessageID: Int? {
        didSet { defaults.set(lastMessageID, forKey: "lastMessageID") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastMessageID = defaults.object(forKey: "lastMessageID") as? Int
    }

    static let all: [ReminderMessage] = {
        let groups: [(MessageCategory, [String])] = [
            (.friendly, [
                "Hey! Shall we drink some water?",
                "A little water break? 💧",
                "Just checking on you. Have you had some water?",
                "Hey! It's been a while. How about a glass of water?",
                "Time for a little water break. 💧",
                "Psst… your water glass misses you.",
                "Quick sip? I'll wait. 😊",
                "How about a refreshing glass of water right now?",
                "Hey there! A few sips would be lovely right about now.",
                "Let's grab some water together. Cheers! 🥤",
                "Friendly nudge: it's water time!",
                "Your water bottle is waving at you. 👋",
            ]),
            (.funny, [
                "Your plants are hydrated. What about you? 🌱",
                "Water is calling. Don't ignore it! 📞",
                "Your body isn't running on coffee alone! ☕️",
                "Your body called. It needs some hydration!",
                "Breaking news: local human forgets to drink water. Don't be that human. 📰",
                "H₂O my goodness, it's water time!",
                "Be like a fish. Stay near water. 🐟",
                "Even cacti drink water sometimes. 🌵",
                "This is your friendly neighbourhood water reminder. 🕸️",
                "Sip happens. Make it happen now.",
                "Water you waiting for? 💧",
                "I'd tell you a water joke, but it might not sink in. Have a sip first.",
            ]),
            (.motivational, [
                "One glass closer to your daily goal!",
                "Keep going. You're doing great! 💪",
                "Small habits create big changes.",
                "Every sip counts. Let's do this!",
                "Champions hydrate. Grab that glass! 🏆",
                "You've got this — one more glass!",
                "Consistency wins. Time for a sip.",
                "Fuel up! A glass of water and back to crushing it.",
                "Strong habits start with small sips.",
                "A little hydration can make your day better.",
            ]),
            (.caring, [
                "You've been busy. Take a moment for yourself.",
                "Remember to look after yourself. 💙",
                "A little break might feel good right now.",
                "Don't forget to take care of yourself!",
                "Hey, you haven't had water in a while. Everything okay?",
                "Pause, breathe, and take a sip. You deserve it.",
                "Be kind to yourself today — a glass of water is a good start.",
                "Just a gentle reminder that you matter. Have some water. 💙",
                "Take it easy for a minute. Water first, then back to it.",
                "Rest your eyes, stretch a little, and have a sip.",
            ]),
            (.workBreak, [
                "You've been working hard. Take a sip!",
                "Step away from the screen for a sec — water break! 🖥️",
                "Your inbox can wait 30 seconds. Water first.",
                "Between tasks? Perfect moment for a glass of water.",
                "Long meeting? Sneak in a sip. 🤫",
                "Save your work, grab some water, come back refreshed.",
                "Quick stretch and a sip before the next task?",
                "Your to-do list will still be there. Hydrate first! ✅",
            ]),
            (.goal, [
                "Let's complete today's hydration goal!",
                "Only {remaining} to go. You can do it!",
                "You're {percent} of the way there — keep it flowing!",
                "So close! {remaining} left to hit today's goal. 🎯",
                "Let's finish today's goal strong! 💪",
                "{consumed} down. Let's top it off!",
                "The finish line is in sight — {remaining} to go! 🏁",
                "One more glass and you're nearly there!",
            ]),
            (.minimal, [
                "Time to drink water.",
                "Hydration reminder.",
                "Water break.",
                "Drink a glass of water.",
                "Reminder: hydrate.",
                "{remaining} left for today.",
                "Scheduled water break.",
                "Time for a glass.",
                "Sip reminder.",
                "Stay hydrated.",
            ]),
        ]
        var id = 0
        var result: [ReminderMessage] = []
        for (category, templates) in groups {
            for t in templates {
                result.append(ReminderMessage(id: id, category: category, template: t))
                id += 1
            }
        }
        return result
    }()

    static func messages(in category: MessageCategory) -> [ReminderMessage] {
        all.filter { $0.category == category }
    }

    static func weights(for personality: Personality) -> [MessageCategory: Int] {
        switch personality {
        case .friendlyFriend: return [.friendly: 4, .caring: 3, .workBreak: 2, .motivational: 1]
        case .funnyBuddy: return [.funny: 6, .friendly: 1, .workBreak: 1]
        case .motivationalCoach: return [.motivational: 5, .goal: 2, .workBreak: 1]
        case .minimalAssistant: return [.minimal: 1]
        }
    }

    func nextMessage(personality: Personality, context: MessageContext) -> String {
        var generator = SystemRandomNumberGenerator()
        return nextMessage(personality: personality, context: context, using: &generator)
    }

    func nextMessage<G: RandomNumberGenerator>(personality: Personality, context: MessageContext,
                                               using rng: inout G) -> String {
        let category = pickCategory(personality: personality, progress: context.progress, using: &rng)
        var pool = Self.messages(in: category).filter { $0.id != lastMessageID }
        if pool.isEmpty { pool = Self.all.filter { $0.id != lastMessageID } }
        let message = pool.randomElement(using: &rng)!
        lastMessageID = message.id
        return Self.render(message.template, context: context)
    }

    private func pickCategory<G: RandomNumberGenerator>(personality: Personality, progress: Double,
                                                        using rng: inout G) -> MessageCategory {
        // Once you're well on the way, goal-focused messages show up more often.
        if personality != .minimalAssistant, progress >= 0.6, progress < 1, Int.random(in: 0..<10, using: &rng) < 4 {
            return .goal
        }
        let weights = Self.weights(for: personality)
        let total = weights.values.reduce(0, +)
        var roll = Int.random(in: 0..<total, using: &rng)
        for (category, weight) in weights.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            if roll < weight { return category }
            roll -= weight
        }
        return .friendly
    }

    static func render(_ template: String, context: MessageContext) -> String {
        template
            .replacingOccurrences(of: "{remaining}", with: context.remaining)
            .replacingOccurrences(of: "{consumed}", with: context.consumed)
            .replacingOccurrences(of: "{percent}", with: "\(Int((context.progress * 100).rounded()))%")
    }

    // MARK: - Greetings

    enum DayPart { case morning, afternoon, evening, night }

    static func dayPart(for date: Date = Date()) -> DayPart {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default: return .night
        }
    }

    static func greetingTitle(for date: Date = Date()) -> String {
        switch dayPart(for: date) {
        case .morning: return "Good morning! 👋"
        case .afternoon: return "Good afternoon! 👋"
        case .evening: return "Good evening! 👋"
        case .night: return "Hello, night owl 🌙"
        }
    }

    static func greetingSubtitle(personality: Personality, date: Date = Date()) -> String {
        let part = dayPart(for: date)
        switch personality {
        case .minimalAssistant:
            return "Let's stay hydrated today."
        case .funnyBuddy:
            switch part {
            case .morning: return "Rise and hydrate, sunshine!"
            case .afternoon: return "Halfway through the day. Still a sponge?"
            case .evening: return "Evening sips are the best sips."
            case .night: return "Even night owls need water. 🦉"
            }
        case .motivationalCoach:
            switch part {
            case .morning: return "New day, new goal. Let's go! 💪"
            case .afternoon: return "Keep the momentum going!"
            case .evening: return "Let's finish the day strong!"
            case .night: return "Rest well — tomorrow we go again."
            }
        case .friendlyFriend:
            switch part {
            case .morning: return "Good morning! Let's start fresh."
            case .afternoon: return "Hope your day is going well!"
            case .evening: return "Let's finish the day strong!"
            case .night: return "Don't stay up too late!"
            }
        }
    }
}
