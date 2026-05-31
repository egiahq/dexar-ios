import SwiftUI

@main
struct DexarApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

extension Color {
    init(hex: String, alpha: Double = 1.0) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        let scanner = Scanner(string: cleanHex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
    }

    static let appBackground = Color(light: Color(hex: "#FFFFFF"), dark: Color(hex: "#0C090C"))
    static let appSecondaryBackground = Color(light: Color(hex: "#F3F1F3"), dark: Color(hex: "#1D161E"))
    static let appTertiaryBackground = Color(light: Color(hex: "#E7E4E7"), dark: Color(hex: "#2A212C"))
    static let appForeground = Color(light: Color(hex: "#0C090C"), dark: Color(hex: "#FAFAFA"))
    static let appMutedForeground = Color(light: Color(hex: "#79697B"), dark: Color(hex: "#A89EA9"))
    static let appPrimary = Color(light: Color(hex: "#1D161E"), dark: Color(hex: "#E7E4E7"))
    static let appPrimaryForeground = Color(light: Color(hex: "#FAFAFA"), dark: Color(hex: "#1D161E"))
    static let appDestructive = Color(light: Color(hex: "#E7000B"), dark: Color(hex: "#FF6467"))
    static let appBorder = Color(light: Color(hex: "#E7E4E7"), dark: Color.white.opacity(0.1))
}

struct SpringButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

extension Animation {
    static let snappySpring = Animation.spring(response: 0.35, dampingFraction: 0.82)
    static let bouncySpring = Animation.spring(response: 0.38, dampingFraction: 0.65)
    static let quickSpring = Animation.spring(response: 0.22, dampingFraction: 0.75)
}
