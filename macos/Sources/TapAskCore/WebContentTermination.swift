public enum WebContentTerminationAction: Equatable, Sendable {
    case reloadNow
    case deferUntilShown
}

/// Login windows recover immediately; hidden provider pages wait until displayed.
public func webContentTerminationAction(isMainWindow: Bool, isDisplayed: Bool) -> WebContentTerminationAction {
    isMainWindow && !isDisplayed ? .deferUntilShown : .reloadNow
}
