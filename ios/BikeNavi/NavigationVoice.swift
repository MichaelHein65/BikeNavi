import AVFoundation

/// Resolve on every utterance so downloads/removals take effect immediately.
enum NavigationVoice {
    struct Candidate {
        let identifier: String
        let name: String
        let language: String
        let quality: Int
        var novelty = false

        var isSiri: Bool {
            identifier.lowercased().contains(".siri") || name.lowercased().contains("siri")
        }

        init(identifier: String, name: String, language: String = "de-DE", quality: Int, novelty: Bool = false) {
            self.identifier = identifier; self.name = name; self.language = language
            self.quality = quality; self.novelty = novelty
        }
        init(_ voice: AVSpeechSynthesisVoice) {
            self.init(identifier: voice.identifier, name: voice.name, language: voice.language,
                      quality: voice.quality.rawValue, novelty: voice.voiceTraits.contains(.isNoveltyVoice))
        }
    }

    static func ranked(_ candidates: [Candidate]) -> [Candidate] {
        candidates.filter {
            $0.language.hasPrefix("de-") && !$0.novelty
                && !$0.identifier.lowercased().contains("eloquence")
                && $0.name.lowercased() != "eddy"
                && ($0.quality >= AVSpeechSynthesisVoiceQuality.premium.rawValue || $0.isSiri)
        }.sorted {
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            if ($0.language == "de-DE") != ($1.language == "de-DE") { return $0.language == "de-DE" }
            if ($0.name == "Anna") != ($1.name == "Anna") { return $0.name == "Anna" }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.identifier < $1.identifier
        }
    }

    static func selectedIdentifier(_ saved: String, candidates: [Candidate]) -> String? {
        let suitable = ranked(candidates)
        return suitable.first { $0.identifier == saved }?.identifier ?? suitable.first?.identifier
    }

    static var available: [AVSpeechSynthesisVoice] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        return ranked(voices.map(Candidate.init)).compactMap { candidate in
            voices.first { $0.identifier == candidate.identifier }
        }
    }

    static func selected(_ identifier: String) -> AVSpeechSynthesisVoice? {
        let voices = available
        // Never fall back to the system language default: that may be Eddy again.
        let selectedID = selectedIdentifier(identifier, candidates: voices.map(Candidate.init))
        return voices.first { $0.identifier == selectedID }
    }

    static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        if Candidate(voice).isSiri { return "\(voice.name) · Siri · \(voice.language)" }
        let quality: String
        switch voice.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Hochwertig"
        default: quality = "Standard"
        }
        return "\(voice.name) · \(quality) · \(voice.language)"
    }
}
