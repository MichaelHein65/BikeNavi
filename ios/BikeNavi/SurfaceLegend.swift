import SwiftUI

extension SurfaceKind {
    var color: Color {
        switch self {
        case .paved: Color(red: 0.08, green: 0.42, blue: 0.76)
        case .paving: Color(red: 0.50, green: 0.30, blue: 0.71)
        case .gravel: Color(red: 0.72, green: 0.45, blue: 0.00)
        case .natural: Color(red: 0.53, green: 0.26, blue: 0.14)
        case .other: Color(red: 0.00, green: 0.49, blue: 0.49)
        case .unknown: Color(red: 0.40, green: 0.44, blue: 0.48)
        }
    }
}

struct SurfaceLegend: View {
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 6) {
            ForEach(SurfaceKind.allCases) { kind in
                HStack(spacing: 5) {
                    Capsule().fill(kind.color).frame(width: 18, height: 5)
                        .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 0.5))
                    Text(kind.title).foregroundStyle(Theme.secondaryInk)
                }.font(.caption2).accessibilityElement(children: .combine)
            }
        }.accessibilityLabel("Farben des Untergrunds")
    }
}
