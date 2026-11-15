import AppKit
import SwiftUI

/// Keep placeholder, insertion point and typed text in the same native text container.
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = PlaceholderTextView(frame:.zero)
        editor.isRichText = false
        editor.drawsBackground = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainerInset = NSSize(width:0,height:6)
        editor.font = .systemFont(ofSize:14)
        editor.textColor = NSColor(Palette.ink)
        editor.insertionPointColor = NSColor(Palette.accent)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        editor.defaultParagraphStyle = paragraph
        editor.setAccessibilityLabel("我的理解")
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PlaceholderTextView else { return }
        if editor.string != text && !editor.hasMarkedText() { editor.string = text }
        editor.isEditable = isEditable
        editor.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        init(_ parent: NoteEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            editor.needsDisplay = true
        }
    }
}

final class PlaceholderTextView: NSTextView {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        needsDisplay = true
        return result
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, window?.firstResponder !== self else { return }
        let origin = textContainerOrigin
        let rect = NSRect(x:origin.x,y:origin.y,width:max(0,bounds.width-origin.x*2),height:bounds.height-origin.y)
        ("如果讲给朋友听，你会怎么解释？" as NSString).draw(in:rect,withAttributes:[
            .font:font ?? NSFont.systemFont(ofSize:14),
            .foregroundColor:NSColor(Palette.secondary),
            .paragraphStyle:defaultParagraphStyle ?? NSParagraphStyle.default
        ])
    }
}
