import Foundation

extension TravelMode {
    static let homeModes: [TravelMode] = [.cycling, .car, .hiking, .bikeAndHike, .sea]
    var homeTitle: String {
        switch self {
        case .cycling: "Fahrrad"
        case .car: "Auto"
        case .hiking: "Wandern"
        case .bikeAndHike: "Fahrrad & Wandern"
        case .sea: "Segeln"
        }
    }
    var homeSubtitle: String {
        switch self {
        case .cycling: "Deine nächste Radtour"
        case .car: "Entspannt ans Ziel"
        case .hiking: "Schritt für Schritt"
        case .bikeAndHike: "Auf Rädern und zu Fuß"
        case .sea: "Dein Tag auf dem Wasser"
        }
    }
    var homeAsset: String { "Home" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var supportsBike: Bool { self == .cycling || self == .bikeAndHike }
}

enum ApplicationWorkspace {
    static func newPlan(mode: TravelMode, profile: RidingProfile? = nil) -> TourDocument {
        var plan = TourDocument()
        if let profile, profile.mode == mode { plan.profile = profile }
        plan.profile.mode = mode
        return plan
    }

    /// An application resumes its own draft, never converts another application's route.
    static func plan(mode: TravelMode, current: TourDocument, records: [SavedRecord], preferredID: UUID?) -> TourDocument {
        if current.kind == .plan && current.profile.mode == mode { return current }
        let plans = records.filter { !$0.deleted && $0.document.kind == .plan && $0.document.profile.mode == mode }
        if let preferredID, let saved = plans.first(where: { $0.id == preferredID }) { return saved.document }
        if let latest = plans.max(by: { $0.document.updatedAt < $1.document.updatedAt }) { return latest.document }
        return newPlan(mode: mode)
    }
}
