import Core
import SwiftUI
import UIKit

// MARK: - Screen

public extension View {
    /// Vanilla page background behind everything, including under the bars.
    func dsScreen() -> some View {
        background(DS.Colors.background.ignoresSafeArea())
    }

    func dsCard(padding: CGFloat = DS.Spacing.m) -> some View {
        modifier(CardModifier(padding: padding, fill: DS.Colors.surface))
    }

    func dsTinted(_ tint: DS.Tint, padding: CGFloat = DS.Spacing.m) -> some View {
        modifier(CardModifier(padding: padding, fill: tint.fill, border: .clear))
    }
}

private struct CardModifier: ViewModifier {
    let padding: CGFloat
    let fill: Color
    var border: Color = DS.Colors.hairline

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .strokeBorder(border, lineWidth: DS.Size.hairline)
            )
    }
}

// MARK: - Buttons

public struct PrimaryButtonStyle: ButtonStyle {
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        ZStack {
            configuration.label.opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView().tint(DS.Colors.onAccent)
            }
        }
        .font(DS.Typography.button)
        .foregroundStyle(DS.Colors.onAccent)
        .frame(maxWidth: .infinity, minHeight: DS.Size.buttonHeight)
        .padding(.horizontal, DS.Spacing.m)
        .background(
            configuration.isPressed ? DS.Colors.accentPressed : DS.Colors.accent,
            in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
        )
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Rectangle())
    }
}

/// Leaving actions such as "Sign out": red words on a soft red panel.
public struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.button)
            .foregroundStyle(DS.Colors.critical)
            .frame(maxWidth: .infinity, minHeight: DS.Size.buttonHeight)
            .padding(.horizontal, DS.Spacing.m)
            .background(
                DS.Colors.criticalSoft.opacity(configuration.isPressed ? 0.7 : 1),
                in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.button)
            .foregroundStyle(DS.Colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: DS.Size.buttonHeight)
            .padding(.horizontal, DS.Spacing.m)
            .background(
                configuration.isPressed ? DS.Colors.hairline : DS.Colors.sunken,
                in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var dsPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func dsPrimary(isLoading: Bool) -> PrimaryButtonStyle { PrimaryButtonStyle(isLoading: isLoading) }
}

public extension ButtonStyle where Self == DestructiveButtonStyle {
    static var dsDestructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var dsSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Text field

/// No box: the words sit on the page. The prompt (see `dsPrompt`) says what to write there.
public struct DSTextFieldStyle: TextFieldStyle {
    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(DS.Typography.body)
            .foregroundStyle(DS.Colors.textPrimary)
            .tint(DS.Colors.accent)
            .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
    }
}

public extension TextFieldStyle where Self == DSTextFieldStyle {
    static var ds: DSTextFieldStyle { DSTextFieldStyle() }
}

/// Placeholder text in the secondary color, so it stays readable (AA) without a box around it.
public func dsPrompt(_ text: String) -> Text {
    Text(text).foregroundStyle(DS.Colors.textSecondary)
}

// MARK: - Pieces

/// A round pastel badge with a symbol: medicine, exercise, instruction, visit.
public struct TintIcon: View {
    private let symbol: String
    private let tint: DS.Tint
    private let size: CGFloat

    public init(symbol: String, tint: DS.Tint, size: CGFloat = DS.Size.icon) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    public init(kind: PlanItem.Kind, size: CGFloat = DS.Size.icon) {
        self.init(symbol: DS.Symbols.of(kind), tint: DS.Tints.of(kind), size: size)
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint.ink)
            .frame(width: size, height: size)
            .background(tint.fill, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Small label above a section ("THIS MORNING").
public struct SectionLabel: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(DS.Typography.label)
            .foregroundStyle(DS.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The big round "done" control of a task row. Filled sage with a check when done.
public struct CheckCircle: View {
    private let isDone: Bool

    public init(isDone: Bool) {
        self.isDone = isDone
    }

    public var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isDone ? DS.Colors.accent : DS.Colors.hairline, lineWidth: 3)
                .background(Circle().fill(isDone ? DS.Colors.accent : DS.Colors.surface))
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DS.Colors.onAccent)
            }
        }
        .frame(width: 44, height: 44)
        .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

/// The CareHold logo: `wordmark.png` when exported from assets/logo.png, else the name in serif.
public struct Wordmark: View {
    private let height: CGFloat

    public init(height: CGFloat = 44) {
        self.height = height
    }

    public var body: some View {
        Group {
            if let image = UIImage(named: "wordmark", in: .module, with: nil) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
            } else {
                Text("CareHold")
                    .font(DS.Typography.brand)
                    .foregroundStyle(DS.Colors.accent)
            }
        }
        .accessibilityLabel("CareHold")
    }
}

/// Calm empty state: an icon, one sentence, optionally one action.
public struct EmptyNote: View {
    private let symbol: String
    private let text: String

    public init(symbol: String, text: String) {
        self.symbol = symbol
        self.text = text
    }

    public var body: some View {
        VStack(spacing: DS.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(DS.Colors.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.l)
    }
}

/// Inline error under a form or list, announced to VoiceOver by the caller.
public struct ErrorText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(DS.Typography.secondary)
            .foregroundStyle(DS.Colors.critical)
    }
}
