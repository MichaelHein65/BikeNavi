import AVFoundation

/// Small hardware boundary so routing and session release can be tested without a car.
protocol NavigationAudioRouting {
    var usesCarPlay: Bool { get }
    var handsFreeInputID: String? { get }
    func configure(_ category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) throws
    func activate() throws
    func preferInput(_ identifier: String?) throws
    func deactivate() throws
}

private struct SystemNavigationAudioRouting: NavigationAudioRouting {
    let session = AVAudioSession.sharedInstance()
    var usesCarPlay: Bool { session.currentRoute.outputs.contains { $0.portType == .carAudio } }
    var handsFreeInputID: String? {
        let inputs = session.availableInputs ?? []
        // Retain the already chosen hands-free device if several are paired.
        return session.currentRoute.inputs.first { $0.portType == .bluetoothHFP }?.uid
            ?? inputs.first { $0.portType == .bluetoothHFP }?.uid
    }
    func configure(_ category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) throws {
        try session.setCategory(category, mode: .voicePrompt, options: options)
    }
    func activate() throws { try session.setActive(true) }
    func preferInput(_ identifier: String?) throws {
        if let identifier {
            guard let port = session.availableInputs?.first(where: { $0.uid == identifier }) else {
                throw APIError(status: 0, message: "Bluetooth-Freisprecheinrichtung wurde getrennt.")
            }
            // HFP couples input and output. Selecting this input selects the phone channel.
            // No recorder, input tap or microphone audio stream is opened.
            try session.setPreferredInput(port)
        } else { try session.setPreferredInput(nil) }
    }
    func deactivate() throws { try session.setActive(false, options: .notifyOthersOnDeactivation) }
}

final class NavigationAudio {
    private let routing: any NavigationAudioRouting
    private(set) var active = false
    private(set) var suppressVolumePreviewUntil = Date.distantPast
    private var selectedInput = false
    private static let mixing: AVAudioSession.CategoryOptions = [.duckOthers, .interruptSpokenAudioAndMixWithOthers]

    init(routing: (any NavigationAudioRouting)? = nil) {
        self.routing = routing ?? SystemNavigationAudioRouting()
    }

    /// Returns true when a paired HFP route was selected; CarPlay retains its prompt channel.
    @discardableResult
    func activate(handsFreePreferred: Bool) throws -> Bool {
        suppressVolumePreviewUntil = Date().addingTimeInterval(1)
        do {
            if handsFreePreferred && !routing.usesCarPlay {
                try routing.configure(.playAndRecord, options: Self.mixing.union([.allowBluetoothHFP, .defaultToSpeaker]))
                try routing.activate(); active = true
                if let identifier = routing.handsFreeInputID {
                    try routing.preferInput(identifier); selectedInput = true
                    return true
                }
                // No paired phone channel: keep normal speaker/headphone playback audible.
                try routing.configure(.playback, options: Self.mixing)
            } else {
                try routing.configure(.playback, options: Self.mixing)
                try routing.activate(); active = true
            }
            return false
        } catch {
            release()
            throw error
        }
    }

    func release() {
        suppressVolumePreviewUntil = Date().addingTimeInterval(1)
        if selectedInput { try? routing.preferInput(nil); selectedInput = false }
        if active {
            do { try routing.deactivate(); active = false }
            catch { return } // Keep ownership so a later completion/cancel can retry.
        }
        // Leave subsequent non-car speech in a playback category, not a phone session.
        try? routing.configure(.playback, options: Self.mixing)
    }
}
