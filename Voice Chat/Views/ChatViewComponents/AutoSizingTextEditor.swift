//
//  AutoSizingTextEditor.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

#if os(macOS)
import AppKit

struct AutoSizingTextEditor: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    @Binding var text: String
    @Binding var height: CGFloat
    var maxLines: Int = 10
    var onOverflowChange: (Bool) -> Void = { _ in }
    var onCommit: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CommitTextView()
        textView.isEditable = true
        textView.font = .systemFont(ofSize: 17)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: InputMetrics.innerLeading, height: InputMetrics.innerTop)
        textView.isRichText = false
        textView.isAutomaticDataDetectionEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.onCommit = onCommit

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        if tv.string != text { tv.string = text }
        guard let textContainer = tv.textContainer else { return }
        let used = tv.layoutManager?.usedRect(for: textContainer) ?? .zero
        let lineH = tv.layoutManager?.defaultLineHeight(for: tv.font ?? .systemFont(ofSize: 17)) ?? 18
        let maxH = CGFloat(maxLines) * lineH + 18
        let newH = min(maxH, max(lineH, used.height + 18))
        let shouldOverflow = (used.height + 18) > (maxH - 1)
        DispatchQueue.main.async {
            if abs(height - newH) > 0.5 { height = newH }
            onOverflowChange(shouldOverflow)
        }

        if let selected = tv.selectedRanges.first as? NSRange {
            tv.scrollRangeToVisible(selected)
        } else {
            let end = NSRange(location: (tv.string as NSString).length, length: 0)
            tv.scrollRangeToVisible(end)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoSizingTextEditor
        weak var textView: NSTextView?

        init(parent: AutoSizingTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            guard let textContainer = tv.textContainer else { return }
            let used = tv.layoutManager?.usedRect(for: textContainer) ?? .zero
            let lineH = tv.layoutManager?.defaultLineHeight(for: tv.font ?? .systemFont(ofSize: 17)) ?? 18
            let maxH = CGFloat(parent.maxLines) * lineH + 18
            let newH = min(maxH, max(lineH, used.height + 18))
            let shouldOverflow = (used.height + 18) > (maxH - 1)
            DispatchQueue.main.async {
                if abs(self.parent.height - newH) > 0.5 { self.parent.height = newH }
                self.parent.onOverflowChange(shouldOverflow)
            }

            let end = NSRange(location: (tv.string as NSString).length, length: 0)
            tv.scrollRangeToVisible(end)
        }
    }

    final class CommitTextView: NSTextView {
        var onCommit: () -> Void = {}
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 {
                if event.modifierFlags.contains(.shift) {
                    super.keyDown(with: event)
                } else {
                    self.window?.makeFirstResponder(nil)
                    onCommit()
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

#else

import UIKit

struct AutoSizingTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var maxLines: Int = 6
    var onOverflowChange: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 17)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(
            top: InputMetrics.innerTop,
            left: InputMetrics.innerLeading,
            bottom: InputMetrics.innerBottom,
            right: InputMetrics.innerTrailing
        )
        tv.isScrollEnabled = false
        tv.alwaysBounceVertical = true
        tv.showsVerticalScrollIndicator = true
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        recalcHeight(uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    fileprivate func recalcHeight(_ tv: UITextView) {
        let lineH = tv.font?.lineHeight ?? 18
        let maxH = CGFloat(maxLines) * lineH + tv.textContainerInset.top + tv.textContainerInset.bottom
        let fitting = tv.sizeThatFits(CGSize(width: tv.bounds.width, height: .greatestFiniteMagnitude)).height
        let newH = min(maxH, max(lineH, fitting))

        let shouldScroll = fitting > (maxH - 1)
        if tv.isScrollEnabled != shouldScroll {
            tv.isScrollEnabled = shouldScroll
        }

        DispatchQueue.main.async {
            if abs(height - newH) > 0.5 { height = newH }
            onOverflowChange(shouldScroll)
        }

        if shouldScroll {
            let end = NSRange(location: (tv.text as NSString).length, length: 0)
            tv.scrollRangeToVisible(end)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoSizingTextEditor
        init(_ parent: AutoSizingTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            parent.recalcHeight(textView)
            if textView.isScrollEnabled {
                let end = NSRange(location: (textView.text as NSString).length, length: 0)
                textView.scrollRangeToVisible(end)
            }
        }
    }
}
#endif
