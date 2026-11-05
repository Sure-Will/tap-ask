public enum PanelToggle {
    public enum Decision: Equatable, Sendable { case show, hide }

    /// The panel floats above every app, so a visible panel is hidden even when
    /// another app has keyboard focus: one press always toggles what the user sees.
    public static func action(isVisible: Bool) -> Decision {
        isVisible ? .hide : .show
    }
}
