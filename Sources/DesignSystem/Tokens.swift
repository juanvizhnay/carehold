import Core
import SwiftUI

/// Design tokens. Views take every color, spacing, radius and font from here, never raw values.
///
/// CareHold is warm and quiet: vanilla paper, white cards, soft pastel tints that tell
/// medicines, exercises, instructions and visits apart, and dark warm text with strong contrast
/// for older eyes. Color is never the only signal: every tint comes with an icon and a word.
public enum DS {
    public enum Colors {
        public static let background = hex(0xFAF6EE)        // vanilla
        public static let surface = hex(0xFFFFFF)
        /// Inputs, secondary buttons, quiet panels.
        public static let sunken = hex(0xF2EBDD)            // beige
        public static let hairline = hex(0xE6DCCB)
        public static let textPrimary = hex(0x2D2823)       // 13.9:1 on vanilla
        public static let textSecondary = hex(0x655C53)     // 6.0:1 on vanilla
        /// Primary actions. White text on it is 5.6:1.
        public static let accent = hex(0x46705F)            // sage
        public static let accentPressed = hex(0x3A5E4F)
        public static let onAccent = hex(0xFFFFFF)
        public static let accentSoft = hex(0xDCE8E0)
        public static let critical = hex(0xA8322A)
        public static let criticalSoft = hex(0xF7DEDA)
    }

    /// Pastel pairs: a soft fill and the dark ink drawn on it (both AA on each other).
    public struct Tint: Sendable {
        public let fill: Color
        public let ink: Color

        public init(fill: Color, ink: Color) {
            self.fill = fill
            self.ink = ink
        }
    }

    public enum Tints {
        public static let medication = Tint(fill: hex(0xF8E3D3), ink: hex(0x8A4E2B))   // peach
        public static let exercise = Tint(fill: hex(0xDDEBDF), ink: hex(0x3A634B))     // sage
        public static let instruction = Tint(fill: hex(0xE7E2F1), ink: hex(0x564C80))  // lavender
        public static let visit = Tint(fill: hex(0xDCE8F3), ink: hex(0x355B7F))        // sky
        public static let reminder = Tint(fill: hex(0xFBEFC9), ink: hex(0x6E581B))     // butter

        public static func of(_ kind: PlanItem.Kind) -> Tint {
            switch kind {
            case .medication: medication
            case .exercise: exercise
            case .instruction: instruction
            }
        }
    }

    public enum Symbols {
        public static func of(_ kind: PlanItem.Kind) -> String {
            switch kind {
            case .medication: "pills.fill"
            case .exercise: "figure.walk"
            case .instruction: "list.bullet.clipboard.fill"
            }
        }

        public static let visit = "calendar"
        public static let reminder = "bell.fill"
        public static let ask = "sparkles"
        public static let message = "bubble.left.and.bubble.right.fill"
    }

    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let s: CGFloat = 12
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
    }

    public enum Radius {
        public static let s: CGFloat = 12
        public static let m: CGFloat = 18
        public static let l: CGFloat = 26
    }

    public enum Size {
        /// Larger than Apple's 44 pt minimum: older hands and tremors.
        public static let tapTarget: CGFloat = 56
        public static let buttonHeight: CGFloat = 60
        public static let icon: CGFloat = 48
        public static let hairline: CGFloat = 1
    }

    /// Every style maps to Dynamic Type, one step larger than the iOS default for readability.
    public enum Typography {
        public static let hero = Font.system(.largeTitle, design: .rounded).weight(.bold)
        public static let title = Font.system(.title, design: .rounded).weight(.bold)
        public static let sectionTitle = Font.system(.title2, design: .rounded).weight(.semibold)
        public static let rowTitle = Font.system(.title3, design: .rounded).weight(.semibold)
        public static let body = Font.system(.title3, design: .rounded)
        public static let secondary = Font.system(.body, design: .rounded)
        public static let label = Font.system(.headline, design: .rounded)
        public static let caption = Font.system(.subheadline, design: .rounded)
        public static let button = Font.system(.title3, design: .rounded).weight(.semibold)
        /// The brand name when the logo image is missing.
        public static let brand = Font.system(.largeTitle, design: .serif).weight(.semibold)
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
