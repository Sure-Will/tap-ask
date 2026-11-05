import AppKit
import TapAskCore

@MainActor
final class PageLoadOverlayView: NSView {
    private let spinner = NSProgressIndicator()
    private let heading = NSTextField(labelWithString: "")
    private let reason = NSTextField(labelWithString: "")
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private var loadingTask: Task<Void, Never>?
    var onRetry: (() -> Void)?

    init() {
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.78).cgColor
        layer?.cornerRadius = 12
        appearance = NSAppearance(named: .darkAqua)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        heading.font = .systemFont(ofSize: 13, weight: .medium)
        heading.textColor = NSColor(white: 1, alpha: 0.95)
        heading.alignment = .center
        reason.font = .systemFont(ofSize: 11)
        reason.textColor = NSColor(white: 1, alpha: 0.75)
        reason.alignment = .center
        retryButton.bezelStyle = .rounded
        retryButton.controlSize = .small
        retryButton.target = self
        retryButton.action = #selector(retry)

        let stack = NSStackView(views: [spinner, heading, reason, retryButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }

    required init?(coder: NSCoder) { nil }

    deinit { loadingTask?.cancel() }

    func update(_ state: PageLoadState, providerName: String) {
        update(state, loadingMessage: "正在打开 \(providerName)…",
               failureMessage: "\(providerName) 打不开", canRetry: true)
    }

    func update(_ state: PageLoadState, loadingMessage: String, failureMessage: String, canRetry: Bool) {
        loadingTask?.cancel()
        loadingTask = nil
        spinner.stopAnimation(nil)
        isHidden = true
        switch state {
        case .idle, .loaded:
            break
        case .loading:
            heading.stringValue = loadingMessage
            spinner.isHidden = false
            reason.isHidden = true
            retryButton.isHidden = true
            loadingTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(400)) }
                catch { return } // A commit or provider switch cancels the pending prompt.
                guard let self else { return }
                self.isHidden = false
                self.spinner.startAnimation(nil)
                self.loadingTask = nil
            }
        case let .failed(failure):
            heading.stringValue = failureMessage
            reason.stringValue = failure.reason + (canRetry ? "" : "，请关闭后重新登录")
            spinner.isHidden = true
            reason.isHidden = false
            retryButton.isHidden = !canRetry
            isHidden = false
        }
    }

    @objc private func retry() { onRetry?() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : super.hitTest(point)
    }
}
