import SwiftUI

enum Theme {
    // MARK: - Colors
    
    enum Colors {
        /// Deep dawn purple - primary accent
        static let dawnPurple = Color(red: 0.39, green: 0.29, blue: 0.64)
        
        /// Warm sunrise orange
        static let sunriseOrange = Color(red: 0.96, green: 0.55, blue: 0.29)
        
        /// Golden morning yellow
        static let morningGold = Color(red: 0.98, green: 0.78, blue: 0.35)
        
        /// Soft dawn pink
        static let dawnPink = Color(red: 0.94, green: 0.64, blue: 0.68)
        
        /// Sky gradient start (dawn blue)
        static let skyStart = Color(red: 0.25, green: 0.32, blue: 0.71)
        
        /// Sky gradient mid (morning teal)
        static let skyMid = Color(red: 0.35, green: 0.56, blue: 0.75)
        
        /// Sky gradient end (daylight)
        static let skyEnd = Color(red: 0.68, green: 0.85, blue: 0.90)
        
        /// Background - follows the system surface in light and dark mode
        static let background = Color(uiColor: .systemBackground)

        /// Card/elevated surface
        static let surface = Color(uiColor: .secondarySystemBackground)

        /// More elevated card surface for dense dashboard content
        static let elevatedSurface = Color(uiColor: .tertiarySystemBackground)

        /// Subtle separator/border color for custom cards
        static let hairline = Color(uiColor: .separator).opacity(0.24)

        /// Success/healthy status color
        static let success = Color(red: 0.16, green: 0.62, blue: 0.39)

        /// Calm secondary accent for Home/status metadata
        static let morningTeal = Color(red: 0.16, green: 0.55, blue: 0.61)

        /// Primary text that adapts to the current color scheme
        static let textPrimary = Color.primary

        /// Secondary/muted text
        static let textSecondary = Color.secondary

        /// Tertiary/placeholder text
        static let textTertiary = Color(uiColor: .tertiaryLabel)
        
        /// Primary accent color (dawn purple)
        static let primary = dawnPurple
        
        /// Warning/error color (sunrise orange)
        static let warning = sunriseOrange
    }
    
    // MARK: - Gradients
    
    enum Gradients {
        /// Full sunrise gradient from night through dawn to day
        static let sunrise = LinearGradient(
            colors: [
                Colors.background,
                Colors.dawnPurple,
                Colors.sunriseOrange,
                Colors.morningGold,
                Colors.skyEnd
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        
        /// Dawn sky gradient (pre-sunrise)
        static let dawnSky = LinearGradient(
            colors: [
                Colors.skyStart,
                Colors.skyMid,
                Colors.skyEnd
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        /// Warm glow gradient for accents
        static let warmGlow = LinearGradient(
            colors: [
                Colors.dawnPink,
                Colors.sunriseOrange,
                Colors.morningGold
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        
        /// Primary button gradient
        static let primaryButton = LinearGradient(
            colors: [
                Colors.dawnPurple,
                Colors.sunriseOrange
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        /// App background wash that stays quiet behind cards and forms
        static let appBackground = LinearGradient(
            colors: [
                Colors.skyEnd.opacity(0.20),
                Colors.background,
                Colors.dawnPink.opacity(0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Compact dashboard accent - a true dawn sky, deep purple into sunrise
        static let dashboard = LinearGradient(
            colors: [
                Colors.dawnPurple,
                Colors.dawnPurple.opacity(0.92),
                Colors.dawnPink.opacity(0.95),
                Colors.sunriseOrange
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Soft radial sun glow for hero artwork and card decoration
        static let sunGlow = RadialGradient(
            colors: [
                Colors.morningGold.opacity(0.55),
                Colors.sunriseOrange.opacity(0.25),
                Color.clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: 160
        )
    }
    
    // MARK: - Typography
    
    enum Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title1 = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 22, weight: .bold, design: .rounded)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 17, weight: .regular, design: .rounded)
        static let bodyBold = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let callout = Font.system(size: 16, weight: .regular, design: .rounded)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .rounded)
        static let footnote = Font.system(size: 13, weight: .regular, design: .rounded)
        static let caption1 = Font.system(size: 12, weight: .regular, design: .rounded)
        static let caption2 = Font.system(size: 11, weight: .regular, design: .rounded)
        static let caption = Font.system(size: 12, weight: .regular, design: .rounded)
    }
    
    // MARK: - Spacing
    
    enum Spacing {
        static let xxSmall: CGFloat = 4
        static let xSmall: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 24
        static let xxLarge: CGFloat = 32
        static let xxxLarge: CGFloat = 48
    }
    
    // MARK: - Radius
    
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 24
        static let circle: CGFloat = 9999
    }
}
