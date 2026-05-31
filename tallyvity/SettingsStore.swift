import Foundation

@Observable
final class SettingsStore {

    enum WhisperModel: String, CaseIterable, Identifiable {
        case tiny   = "openai_whisper-tiny"
        case base   = "openai_whisper-base"
        case small  = "openai_whisper-small_216MB"
        case large  = "openai_whisper-large-v3-v20240930_626MB"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .tiny:  "Tiny · fastest, light (recommended)"
            case .base:  "Base · fast, balanced"
            case .small: "Small · balanced"
            case .large: "Large · best accuracy, slow"
            }
        }
    }

    enum Voice: String, CaseIterable, Identifiable {
        case ryan, aiden, onoAnna, sohee, eric, dylan, serena, vivian, uncleFu

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .ryan:    "Ryan"
            case .aiden:   "Aiden"
            case .onoAnna: "Ono Anna"
            case .sohee:   "Sohee"
            case .eric:    "Eric"
            case .dylan:   "Dylan"
            case .serena:  "Serena"
            case .vivian:  "Vivian"
            case .uncleFu: "Uncle Fu"
            }
        }
    }

    private let defaults = UserDefaults.standard

    var whisperModel: WhisperModel {
        didSet { defaults.set(whisperModel.rawValue, forKey: "whisperModel") }
    }

    var voice: Voice {
        didSet { defaults.set(voice.rawValue, forKey: "voice") }
    }

    var userName: String {
        didSet { defaults.set(userName, forKey: "userName") }
    }

    var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: "onboardingComplete") }
    }

    var peakHourNotificationEnabled: Bool {
        didSet { defaults.set(peakHourNotificationEnabled, forKey: "peakHourNotificationEnabled") }
    }

    var peakNotificationHours: [Int] {
        didSet { defaults.set(peakNotificationHours, forKey: "peakNotificationHours") }
    }

    init() {
        let m = defaults.string(forKey: "whisperModel") ?? ""
        whisperModel = WhisperModel(rawValue: m) ?? .tiny
        let v = defaults.string(forKey: "voice") ?? ""
        voice = Voice(rawValue: v) ?? .dylan
        userName = defaults.string(forKey: "userName") ?? ""
        onboardingComplete = defaults.bool(forKey: "onboardingComplete")
        peakHourNotificationEnabled = defaults.bool(forKey: "peakHourNotificationEnabled")
        peakNotificationHours = defaults.array(forKey: "peakNotificationHours") as? [Int] ?? []
    }
}
