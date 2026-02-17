import SwiftUI

enum AppTheme {
    enum Colors {
        static let background: Color = themed("#0D0D0F", fallback: .black)
        static let primary: Color = themed("#00F5FF", fallback: .cyan)
        static let secondary: Color = themed("#FE8C10", fallback: .orange)

        static let accent = primary
        static let warning = secondary
        static let statusReady = primary
        static let statusWarning = secondary
        static let statusError = secondary
        static let subtleSurface = primary.opacity(0.12)
    }
}

private extension AppTheme.Colors {
    static func themed(_ hex: String, fallback: Color) -> Color {
        Color(hex: hex) ?? fallback
    }
}

extension View {
    func appThemeRoot() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(AppTheme.Colors.accent)
            .fontDesign(.monospaced)
            .background(AppTheme.Colors.background)
    }
}
