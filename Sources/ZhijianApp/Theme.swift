import SwiftUI
import AppKit

enum Palette {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1)
        })
    }
    static let paper = adaptive(0xFCFBF7, 0x20231F)
    static let sidebar = adaptive(0xEEEFE7, 0x191D19)
    static let index = adaptive(0xF6F6F0, 0x1C201C)
    static let ink = adaptive(0x27332C, 0xE5E9DF)
    static let secondary = adaptive(0x596456, 0xA2AC9F)
    static let accent = adaptive(0x3E624C, 0xA6C4A2)
    static let onAccent = adaptive(0xFFFFFF, 0x18271C)
    static let selection = adaptive(0xE5EBDF, 0x303F31)
    static let rule = adaptive(0xDDDFD4, 0x3B4339)
    static let note = adaptive(0xF0F0E7, 0x2B3128)
    static let rust = adaptive(0x9B553B, 0xE8AF91)
    static let title = Font.custom("Songti SC", size: 36, relativeTo: .largeTitle)
    static let heading = Font.custom("Songti SC", size: 25, relativeTo: .title2)
}

struct QuietIconButton: View {
    let symbol: String
    let label: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 15, weight: .regular)).frame(width: 30, height: 30).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(active ? Palette.accent : Palette.secondary)
            .help(label).accessibilityLabel(label)
    }
}

struct SectionTitle: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
    }
}

struct MossButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).padding(.horizontal, 17).padding(.vertical, 10)
            .foregroundStyle(Palette.onAccent).background(Palette.accent.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    func readingText() -> some View { self.font(.system(size: 16)).lineSpacing(7).foregroundStyle(Palette.ink).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
}
