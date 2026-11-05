public enum PanelToggle {
    public enum Decision: Equatable, Sendable { case show, hide, focus }

    public static func action(isVisible: Bool, isKeyAndActive: Bool) -> Decision {
        if !isVisible { return .show }
        return isKeyAndActive ? .hide : .focus
    }
}
