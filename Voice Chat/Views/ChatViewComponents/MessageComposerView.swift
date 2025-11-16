#if os(iOS) || os(tvOS)

import SwiftUI
import UIKit

struct MessageComposerView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    @Binding var isFirstResponder: Bool

    var placeholder: String
    var maxLines: Int
    var isLoading: Bool
    var trimmedIsEmpty: Bool
    var onSend: () -> Void
    var onStop: () -> Void
    var onVoice: () -> Void
    var onExpand: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ComposerContainerView {
        let view = ComposerContainerView()
        view.textView.delegate = context.coordinator
        context.coordinator.hostView = view
        view.primaryButton.addTarget(context.coordinator, action: #selector(Coordinator.primaryTapped), for: .touchUpInside)
        view.expandButton.addTarget(context.coordinator, action: #selector(Coordinator.expandTapped), for: .touchUpInside)
        return view
    }

    func updateUIView(_ uiView: ComposerContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostView = uiView
        uiView.placeholder = placeholder
        uiView.maxLines = maxLines

        if uiView.textView.text != text {
            uiView.textView.text = text
        }

        uiView.updatePlaceholderVisibility(text: text)
        uiView.configureButtons(isLoading: isLoading, trimmedEmpty: trimmedIsEmpty)

        let metrics = uiView.recalculateHeight()
        context.coordinator.updateMetrics(metrics)

        if isFirstResponder {
            if !uiView.textView.isFirstResponder {
                uiView.textView.becomeFirstResponder()
            }
        } else if uiView.textView.isFirstResponder {
            uiView.textView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MessageComposerView
        weak var hostView: ComposerContainerView?

        init(parent: MessageComposerView) {
            self.parent = parent
        }

        func updateMetrics(_ metrics: ComposerContainerView.HeightMetrics) {
            hostView?.setOverflowing(metrics.isOverflowing)
            DispatchQueue.main.async {
                if abs(self.parent.measuredHeight - metrics.totalHeight) > 0.5 {
                    self.parent.measuredHeight = metrics.totalHeight
                }
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFirstResponder = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFirstResponder = false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            hostView?.updatePlaceholderVisibility(text: parent.text)
            if let metrics = hostView?.recalculateHeight() {
                updateMetrics(metrics)
            }
        }

        @objc func primaryTapped() {
            if parent.isLoading {
                parent.onStop()
            } else if parent.trimmedIsEmpty {
                parent.onVoice()
            } else {
                parent.onSend()
            }
        }

        @objc func expandTapped() {
            parent.onExpand()
        }
    }
}

final class ComposerContainerView: UIView {
    struct HeightMetrics {
        let totalHeight: CGFloat
        let isOverflowing: Bool
    }

    private enum Layout {
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 6
        static let buttonSpacing: CGFloat = 6
        static let cornerRadius: CGFloat = 26
        static let buttonSymbolPointSize: CGFloat = 24
    }

    let containerView = UIView()
    let stackView = UIStackView()
    let textView = UITextView()
    let placeholderLabel = UILabel()
    let buttonStack = UIStackView()
    let expandButton = UIButton(type: .system)
    let primaryButton = UIButton(type: .system)

    var placeholder: String = "" {
        didSet { placeholderLabel.text = placeholder }
    }

    var maxLines: Int = 6

    private var textHeightConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear

        containerView.backgroundColor = UIColor.secondarySystemFill
        containerView.layer.cornerRadius = Layout.cornerRadius
        containerView.layer.cornerCurve = .continuous
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Layout.buttonSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.horizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.horizontalPadding),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.verticalPadding),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Layout.verticalPadding)
        ])

        textView.font = .systemFont(ofSize: 17)
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        placeholderLabel.font = .systemFont(ofSize: 17)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: textView.textContainerInset.left + 2),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.top)
        ])

        buttonStack.axis = .horizontal
        buttonStack.spacing = Layout.buttonSpacing
        buttonStack.alignment = .center
        buttonStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        buttonStack.setContentHuggingPriority(.required, for: .horizontal)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: Layout.buttonSymbolPointSize, weight: .semibold)
        primaryButton.setPreferredSymbolConfiguration(symbolConfig, forImageIn: .normal)
        primaryButton.tintColor = UIColor(ChatTheme.accent)
        primaryButton.accessibilityLabel = "Send"
        primaryButton.contentEdgeInsets = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)

        expandButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: symbolConfig), for: .normal)
        expandButton.tintColor = .secondaryLabel
        expandButton.accessibilityLabel = "Open full screen editor"
        expandButton.isHidden = true
        expandButton.contentEdgeInsets = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)

        buttonStack.addArrangedSubview(expandButton)
        buttonStack.addArrangedSubview(primaryButton)

        stackView.addArrangedSubview(textView)
        stackView.addArrangedSubview(buttonStack)

        textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: InputMetrics.defaultHeight)
        textHeightConstraint.priority = .defaultHigh
        textHeightConstraint.isActive = true
    }

    func configureButtons(isLoading: Bool, trimmedEmpty: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: Layout.buttonSymbolPointSize, weight: .semibold)
        if isLoading {
            primaryButton.setImage(UIImage(systemName: "stop.circle.fill", withConfiguration: config), for: .normal)
            primaryButton.tintColor = .systemRed
            primaryButton.accessibilityLabel = "Stop Generation"
        } else if trimmedEmpty {
            primaryButton.setImage(UIImage(systemName: "waveform.circle.fill", withConfiguration: config), for: .normal)
            primaryButton.tintColor = UIColor(ChatTheme.accent)
            primaryButton.accessibilityLabel = "Start Realtime Voice Conversation"
        } else {
            primaryButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config), for: .normal)
            primaryButton.tintColor = UIColor(ChatTheme.accent)
            primaryButton.accessibilityLabel = "Send Message"
        }
    }

    func setOverflowing(_ overflowing: Bool) {
        expandButton.isHidden = !overflowing
    }

    func updatePlaceholderVisibility(text: String) {
        placeholderLabel.isHidden = !text.isEmpty
    }

    func recalculateHeight() -> HeightMetrics {
        layoutIfNeeded()
        let availableWidth = max(textView.bounds.width, bounds.width - (Layout.horizontalPadding * 2) - 80)
        let fittingSize = textView.sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude)).height
        let lineHeight = textView.font?.lineHeight ?? 20
        let insetHeight = textView.textContainerInset.top + textView.textContainerInset.bottom
        let minHeight = lineHeight + insetHeight
        let maxHeight = CGFloat(maxLines) * lineHeight + insetHeight
        let clamped = min(maxHeight, max(minHeight, fittingSize))
        let overflowing = fittingSize > (maxHeight - 1)
        textHeightConstraint.constant = clamped
        let totalHeight = clamped + (Layout.verticalPadding * 2)
        return HeightMetrics(totalHeight: totalHeight, isOverflowing: overflowing)
    }
}

#endif
