import AVFoundation

/// Small hardware boundary so routing and session release can be tested without a car.
protocol NavigationAudioRouting {
    var usesCarPlay: Bool { get }
    var handsFreeInputID: String? { get }
    func configure(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws
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
    func configure(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {
        try session.setCategory(category, mode: mode, options: options)
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
    private(set) var fallbackReason: String?
    private var selectedInput = false
    private static let mixing: AVAudioSession.CategoryOptions = [.duckOthers, .interruptSpokenAudioAndMixWithOthers]

    init(routing: (any NavigationAudioRouting)? = nil) {
        self.routing = routing ?? SystemNavigationAudioRouting()
    }

    /// Returns true only when the HFP preference was applied successfully.
    /// A failed phone-channel attempt must not prevent ordinary speech playback.
    @discardableResult
    func activate(handsFreePreferred: Bool) throws -> Bool {
        suppressVolumePreviewUntil = Date().addingTimeInterval(1)
        fallbackReason = nil
        if handsFreePreferred && !routing.usesCarPlay {
            do {
                try perform("Freisprechkanal konfigurieren") {
                    // HFP uses a plain, nonmixing input/output session. The previous
                    // voicePrompt + speaker/mixing configuration was rejected on device (-50).
                    try routing.configure(.playAndRecord, mode: .default, options: [.allowBluetoothHFP])
                }
                try perform("Freisprechkanal aktivieren") { try routing.activate() }
                active = true
                if let identifier = routing.handsFreeInputID {
                    // Also clear a preference if the system partially applies it before throwing.
                    selectedInput = true
                    try perform("Freisprecheinrichtung auswählen") { try routing.preferInput(identifier) }
                    return true
                }
            } catch {
                fallbackReason = error.localizedDescription
            }
            // End the input-capable session before starting ordinary playback, including
            // when Bluetooth is off and there never was a hands-free device.
            release()
            guard !active, !selectedInput else {
                throw Failure(detail: "Freisprechkanal konnte nicht freigegeben werden. Bitte die Hörprobe erneut starten.")
            }
        }
        do {
            try perform("Wiedergabe konfigurieren") { try routing.configure(.playback, mode: .voicePrompt, options: Self.mixing) }
            try perform("Wiedergabe aktivieren") { try routing.activate() }
            active = true
            return false
        } catch {
            release()
            let previous = fallbackReason.map { " Freisprechversuch: " + $0 } ?? ""
            throw Failure(detail: error.localizedDescription + previous)
        }
    }

    var fallbackMessage: String? {
        fallbackReason.map {
            "Freisprechkanal nicht verfügbar. Normale Audioausgabe wird verwendet; im Auto ggf. Bluetooth-Audio wählen. Ursache: " + $0
        }
    }

    static func failureMessage(_ error: Error) -> String {
        "Sprachausgabe konnte nicht aktiviert werden. " + error.localizedDescription
    }

    private struct Failure: LocalizedError {
        let detail: String
        var errorDescription: String? { detail }
    }

    private func perform(_ step: String, _ action: () throws -> Void) throws {
        do { try action() }
        catch {
            let cause = error as NSError
            throw Failure(detail: "\(step): \(cause.localizedDescription) [\(cause.domain), \(cause.code)]")
        }
    }

    func release() {
        suppressVolumePreviewUntil = Date().addingTimeInterval(1)
        if selectedInput {
            do { try routing.preferInput(nil); selectedInput = false }
            catch { /* Keep ownership so the next release retries. */ }
        }
        if active {
            do { try routing.deactivate(); active = false }
            catch { return } // Keep ownership so a later completion/cancel can retry.
        }
        // Leave subsequent non-car speech in a playback category, not a phone session.
        try? routing.configure(.playback, mode: .voicePrompt, options: Self.mixing)
    }
}
