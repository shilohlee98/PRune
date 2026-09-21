import SwiftUI

extension Color {
    static let appBackground = Color(red: 0.047, green: 0.051, blue: 0.057)
    static let panelBackground = Color(red: 0.058, green: 0.062, blue: 0.069)
    static let elevatedBackground = Color(red: 0.095, green: 0.099, blue: 0.108)
    static let selectedBackground = Color(red: 0.119, green: 0.123, blue: 0.134)
    static let subtleBorder = Color.white.opacity(0.065)
    static let mutedText = Color.white.opacity(0.40)
    static let secondaryText = Color.white.opacity(0.59)
}

enum AppButtonEmphasis {
    case primary
    case positive
    case outlined
    case secondary
    case subtle
    case icon
}

struct AppButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let emphasis: AppButtonEmphasis

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .frame(
                minWidth: emphasis == .icon ? 28 : nil,
                minHeight: emphasis == .outlined ? 30 : 28
            )
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(borderColor, lineWidth: emphasis == .secondary ? 0 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .opacity(isEnabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch emphasis {
        case .primary:
            Color.black.opacity(0.84)
        case .positive:
            Color.white.opacity(0.94)
        case .outlined:
            Color.white.opacity(0.86)
        case .secondary:
            Color.secondaryText
        case .subtle, .icon:
            Color.primary.opacity(0.82)
        }
    }

    private var horizontalPadding: CGFloat {
        switch emphasis {
        case .icon:
            0
        case .secondary:
            7
        case .primary, .positive, .outlined, .subtle:
            10
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch emphasis {
        case .primary:
            Color.white.opacity(isPressed ? 0.70 : 0.82)
        case .positive:
            Color(red: 0.16, green: 0.58, blue: 0.29)
                .opacity(isPressed ? 0.78 : 0.96)
        case .outlined:
            Color.white.opacity(isPressed ? 0.11 : 0.045)
        case .secondary:
            Color.clear
        case .subtle:
            Color.white.opacity(isPressed ? 0.09 : 0.055)
        case .icon:
            Color.white.opacity(isPressed ? 0.08 : 0.025)
        }
    }

    private var borderColor: Color {
        switch emphasis {
        case .primary:
            Color.white.opacity(0.28)
        case .positive:
            Color.green.opacity(0.58)
        case .outlined:
            Color.white.opacity(0.22)
        case .secondary:
            Color.clear
        case .subtle:
            Color.white.opacity(0.10)
        case .icon:
            Color.white.opacity(0.07)
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var appPrimary: AppButtonStyle { AppButtonStyle(emphasis: .primary) }
    static var appPositive: AppButtonStyle { AppButtonStyle(emphasis: .positive) }
    static var appOutlined: AppButtonStyle { AppButtonStyle(emphasis: .outlined) }
    static var appSecondary: AppButtonStyle { AppButtonStyle(emphasis: .secondary) }
    static var appSubtle: AppButtonStyle { AppButtonStyle(emphasis: .subtle) }
    static var appIcon: AppButtonStyle { AppButtonStyle(emphasis: .icon) }
}

struct PullRequestGlyph: View {
    let state: CheckState
    var isSelected = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Canvas { context, _ in
                var path = Path()
                path.move(to: CGPoint(x: 5, y: 2))
                path.addLine(to: CGPoint(x: 5, y: 11.5))
                path.move(to: CGPoint(x: 5, y: 6))
                path.addCurve(
                    to: CGPoint(x: 11, y: 9),
                    control1: CGPoint(x: 5, y: 8.2),
                    control2: CGPoint(x: 8.7, y: 9)
                )
                context.stroke(
                    path,
                    with: .color(.white.opacity(0.43)),
                    style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round)
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: 3.35, y: 0.35, width: 3.3, height: 3.3)),
                    with: .color(.white.opacity(0.43))
                )
            }
            .frame(width: 15, height: 15)

            StateDot(state: state)
                .overlay(
                    Circle().stroke(
                        isSelected ? Color.selectedBackground : Color.appBackground,
                        lineWidth: 1.6
                    )
                )
                .offset(x: 1, y: 1)
        }
        .frame(width: 18, height: 18)
    }
}

struct StateDot: View {
    let state: CheckState

    var color: Color {
        switch state {
        case .success: .green
        case .pending: .orange
        case .failed: .red
        case .all: .secondary
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }
}

struct AvatarView: View {
    let label: String
    var size: CGFloat = 21
    var imageURL: URL? = nil

    private var initials: String {
        let parts = label.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.85), .purple.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(size: max(7, size * 0.34), weight: .medium))
                .foregroundStyle(.white)

            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if case let .success(image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .help(label)
    }
}

enum GitHubAvatarURL {
    static func forLogin(_ login: String, size: CGFloat = 42) -> URL? {
        guard !login.isEmpty else { return nil }
        let pixels = max(32, Int(size.rounded(.up)))
        return URL(string: "https://github.com/\(login).png?size=\(pixels)")
    }
}

struct PaneSectionHeader: View {
    let title: String
    var count: Int? = nil
    var isExpanded = true
    var onToggle: (() -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if let onToggle {
            Button(action: onToggle) {
                label
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help(isExpanded ? "Collapse \(title)" : "Expand \(title)")
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
            if let count {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(Color.mutedText)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.mutedText)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
            Spacer()
        }
        .frame(minHeight: 24)
    }
}
