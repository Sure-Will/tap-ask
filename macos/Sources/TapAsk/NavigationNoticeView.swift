import AppKit
import TapAskCore

@MainActor
final class NavigationNoticeView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    private var noticeState = NavigationNoticeState()
    private var dismissalTask: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.78).cgColor
        layer?.cornerRadius = 10
        label.font = .systemFont(ofSize: 11)
        label.textColor = NSColor(white: 1, alpha: 0.95)
        label.alignment = .center
        label.lineBreakMode = .byCharWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { nil }

    deinit { dismissalTask?.cancel() }

    func show(_ notice: NavigationNotice) {
        noticeState = nextNavigationNoticeState(from: noticeState, showing: notice,
                                                at: ProcessInfo.processInfo.systemUptime)
        guard let notice = noticeState.notice else { return }
        dismissalTask?.cancel()
        label.stringValue = notice.message
        isHidden = false
        dismissalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(6)) }
            catch { return } // Replacement or disposal cancels only this pending dismissal.
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        isHidden = true
        label.stringValue = ""
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
