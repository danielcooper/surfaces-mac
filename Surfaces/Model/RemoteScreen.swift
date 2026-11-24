import Foundation

/// A screen as listed by the Surfaces API (`GET /api/screens`).
struct RemoteScreen: Decodable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let surfaceId: String
    let width: Int
    let height: Int
    let scale: Double
    let renderedAt: String?
    let ok: Bool

    var aspectRatio: Double { height > 0 ? Double(width) / Double(height) : 1 }
    var sizeLabel: String { scale == 1 ? "\(width)×\(height)" : "\(width)×\(height) @\(scale.formatted())x" }
}

struct ScreenList: Decodable, Sendable {
    let screens: [RemoteScreen]
}
