import AppKit
import SwiftUI

/// Observes the native reader scroll view without replacing SwiftUI's scroll/input behavior.
struct ReadingScrollObserver: NSViewRepresentable {
    let initialOffset: Double
    let onChange: (Double) -> Void
    func makeNSView(context: Context) -> Marker {
        let marker=Marker()
        marker.initialOffset=initialOffset; marker.onChange=onChange
        return marker
    }
    func updateNSView(_ marker: Marker, context: Context) { marker.onChange=onChange }
    static func dismantleNSView(_ marker: Marker, coordinator: ()) { marker.detach() }

    final class Marker: NSView {
        var initialOffset=0.0
        var onChange: ((Double)->Void)?
        private weak var scroll: NSScrollView?
        private var observation: NSObjectProtocol?
        private var termination: NSObjectProtocol?
        private var pending: DispatchWorkItem?
        private var restored=false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }
        private func attach() {
            guard observation == nil, let scroll=enclosingScrollView else { return }
            self.scroll=scroll
            scroll.contentView.postsBoundsChangedNotifications=true
            observation=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:scroll.contentView,queue:.main) { [weak self] _ in self?.changed() }
            termination=NotificationCenter.default.addObserver(forName:NSApplication.willTerminateNotification,object:nil,queue:.main) { [weak self] _ in self?.report() }
            // Let SwiftUI lay out restored disclosure content before clamping the saved offset.
            DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { [weak self] in
                guard let self, let scroll=self.scroll else { return }
                scroll.layoutSubtreeIfNeeded()
                let maximum=max(0,(scroll.documentView?.bounds.height ?? 0)-scroll.contentView.bounds.height)
                scroll.contentView.scroll(to:NSPoint(x:0,y:min(maximum,max(0,self.initialOffset))))
                scroll.reflectScrolledClipView(scroll.contentView)
                self.restored=true
            }
        }
        private func changed() {
            guard restored else { return }
            pending?.cancel()
            let work=DispatchWorkItem { [weak self] in self?.report() }
            pending=work; DispatchQueue.main.asyncAfter(deadline:.now()+0.2,execute:work)
        }
        private func report() {
            guard restored, let scroll else { return }
            onChange?(max(0,scroll.contentView.bounds.origin.y))
        }
        func detach() {
            pending?.cancel(); report()
            if let observation { NotificationCenter.default.removeObserver(observation) }
            if let termination { NotificationCenter.default.removeObserver(termination) }
            observation=nil; termination=nil; scroll=nil
        }
        deinit {
            if let observation { NotificationCenter.default.removeObserver(observation) }
            if let termination { NotificationCenter.default.removeObserver(termination) }
            pending?.cancel()
        }
    }
}
