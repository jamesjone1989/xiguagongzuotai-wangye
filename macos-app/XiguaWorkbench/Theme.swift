import SwiftUI

enum WorkbenchTheme {
    static let paper = Color(red: 247 / 255, green: 243 / 255, blue: 232 / 255)
    static let paperLight = Color(red: 255 / 255, green: 253 / 255, blue: 247 / 255)
    static let ink = Color(red: 23 / 255, green: 37 / 255, blue: 31 / 255)
    static let muted = Color(red: 113 / 255, green: 128 / 255, blue: 121 / 255)
    static let line = Color(red: 217 / 255, green: 212 / 255, blue: 199 / 255)
    static let green = Color(red: 47 / 255, green: 107 / 255, blue: 85 / 255)
    static let leaf = Color(red: 133 / 255, green: 173 / 255, blue: 116 / 255)
    static let sage = Color(red: 220 / 255, green: 234 / 255, blue: 223 / 255)
    static let red = Color(red: 240 / 255, green: 82 / 255, blue: 76 / 255)
    static let redSoft = Color(red: 249 / 255, green: 216 / 255, blue: 209 / 255)
    static let yellow = Color(red: 242 / 255, green: 199 / 255, blue: 92 / 255)

    static func displayFont(_ size: CGFloat) -> Font {
        .custom("Songti SC", size: size).weight(.bold)
    }
}

extension Color {
    static let workbenchGreen = WorkbenchTheme.green
    static let workbenchYellow = WorkbenchTheme.yellow
    static let workbenchPaper = WorkbenchTheme.paper
}

struct PaperBackground: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(WorkbenchTheme.paper))
            var lines = Path()
            stride(from: CGFloat(0), through: size.height, by: 5).forEach { y in
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(lines, with: .color(WorkbenchTheme.ink.opacity(0.018)), lineWidth: 1)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct HardCard: ViewModifier {
    var fill: Color = WorkbenchTheme.paperLight
    var radius: CGFloat = 22
    var padding: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(WorkbenchTheme.ink, lineWidth: 2.3)
            }
    }
}

struct SoftCard: ViewModifier {
    var fill: Color = WorkbenchTheme.paperLight
    var radius: CGFloat = 14
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(WorkbenchTheme.ink, lineWidth: 1.8)
            }
    }
}

struct OutlineButtonStyle: ButtonStyle {
    var fill = WorkbenchTheme.paperLight
    var pressedFill = WorkbenchTheme.sage

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(WorkbenchTheme.ink)
            .padding(.horizontal, 17)
            .frame(minHeight: 42)
            .background(configuration.isPressed ? pressedFill : fill, in: Capsule())
            .overlay(Capsule().stroke(WorkbenchTheme.ink, lineWidth: 2))
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}

struct SolidButtonStyle: ButtonStyle {
    var fill = WorkbenchTheme.green

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(minHeight: 48)
            .background(fill.opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
            .overlay(Capsule().stroke(WorkbenchTheme.ink, lineWidth: 2))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SquareBrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(WorkbenchTheme.ink)
            .frame(width: 42, height: 38)
            .background(configuration.isPressed ? WorkbenchTheme.sage : WorkbenchTheme.paperLight, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(WorkbenchTheme.ink, lineWidth: 2))
    }
}

extension View {
    func hardCard(
        fill: Color = WorkbenchTheme.paperLight,
        radius: CGFloat = 22,
        shadow: CGFloat = 8,
        padding: CGFloat = 22
    ) -> some View {
        modifier(HardCard(fill: fill, radius: radius, padding: padding))
    }

    func softCard(
        fill: Color = WorkbenchTheme.paperLight,
        radius: CGFloat = 14,
        padding: CGFloat = 16
    ) -> some View {
        modifier(SoftCard(fill: fill, radius: radius, padding: padding))
    }

    func workbenchPanel() -> some View {
        softCard(fill: WorkbenchTheme.paperLight, radius: 14, padding: 18)
    }
}

struct BrandPageHeading: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(WorkbenchTheme.green)
            Text(title)
                .font(WorkbenchTheme.displayFont(46))
                .foregroundStyle(WorkbenchTheme.ink)
                .tracking(-1.6)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(WorkbenchTheme.muted)
            }
        }
    }
}
