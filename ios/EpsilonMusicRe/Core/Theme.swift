import SwiftUI

extension Color {
    /// Epsilon Music signature red (#ED5564) — the Android app's theme seed.
    static let epsAccent = Color(red: 237.0 / 255.0, green: 85.0 / 255.0, blue: 100.0 / 255.0)

    /// Near-black app background.
    static let epsBackground = Color(red: 16.0 / 255.0, green: 16.0 / 255.0, blue: 20.0 / 255.0)

    /// Elevated card surface.
    static let epsSurface = Color(red: 30.0 / 255.0, green: 30.0 / 255.0, blue: 36.0 / 255.0)

    /// Slightly brighter surface for featured tiles.
    static let epsSurfaceHighlighted = Color(red: 40.0 / 255.0, green: 40.0 / 255.0, blue: 48.0 / 255.0)

    static let epsTextPrimary = Color.white
    static let epsTextSecondary = Color(white: 0.64)
}
