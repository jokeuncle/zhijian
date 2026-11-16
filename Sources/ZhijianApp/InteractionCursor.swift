import SwiftUI
import AppKit

extension View {
    /// Apply only to the control's hit area, never a container of reading text.
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(isEnabled ? .link : .default)
        } else {
            content.background(CursorRegion(isEnabled: isEnabled))
        }
    }
}

/// macOS 14 compatibility. AppKit owns cursor restoration and clipping while
/// scrolling; no global cursor push/pop stack or per-hover SwiftUI state.
private struct CursorRegion: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> CursorRegionView { CursorRegionView() }

    func updateNSView(_ view: CursorRegionView, context: Context) {
        guard view.isEnabled != isEnabled else { return }
        view.isEnabled = isEnabled
        view.window?.invalidateCursorRects(for: view)
    }
}

private final class CursorRegionView: NSView {
    var isEnabled = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled && !visibleRect.isEmpty {
            addCursorRect(visibleRect, cursor: .pointingHand)
        }
    }
}

/// Limit the cursor to the disclosure header so expanded text remains selectable.
struct ClickableDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 12)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    configuration.label
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .accessibilityValue(configuration.isExpanded ? "已展开" : "已收起")
            if configuration.isExpanded {
                configuration.content.padding(.leading, 17)
            }
        }
    }
}
