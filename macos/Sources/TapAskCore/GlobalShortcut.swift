import Foundation

public struct ShortcutModifiers: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let shift = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
    public static let supported: Self = [.control, .option, .shift, .command]

    public var symbols: String {
        [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }.map(\.1).joined()
    }
}

/// Physical macOS key codes, independent of AppKit and Carbon registration.
public struct GlobalShortcut: Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: ShortcutModifiers
    public static let defaultShortcut = GlobalShortcut(keyCode: 49, modifiers: .option)!

    public init?(keyCode: UInt16, modifiers: ShortcutModifiers) {
        guard Self.validationMessage(keyCode: keyCode, modifiers: modifiers) == nil else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static func validationMessage(keyCode: UInt16, modifiers: ShortcutModifiers) -> String? {
        guard modifiers.subtracting(.supported).isEmpty else { return "不支持这组修饰键。" }
        guard !modifiers.intersection([.control, .option, .command]).isEmpty else {
            return "请同时按住 ⌘、⌥ 或 ⌃，也可以加上 ⇧。"
        }
        guard keys[keyCode] != nil else { return "请选择字母、数字、标点、空格、方向键或功能键。" }
        return nil
    }

    /// Menu commands follow characters, unlike Carbon's physical key codes.
    public static func menuConflictMessage(keyEquivalent: String, modifiers: ShortcutModifiers) -> String? {
        let key = keyEquivalent.lowercased()
        let commandKeys: Set<String> = ["z", "x", "c", "v", "a", "q", "w", "r", "1", "2", "3", "4", "5", "6", "7", "8", "9", ","]
        if (modifiers == .command && commandKeys.contains(key))
            || (modifiers == [.command, .shift] && key == "z")
            || (modifiers == .option && ["\u{F700}", "\u{F701}"].contains(key)) {
            return "这组快捷键已用于 TapAsk 的其他操作，请换一组。"
        }
        return nil
    }

    public var propertyList: [String: Int] { ["keyCode": Int(keyCode), "modifiers": Int(modifiers.rawValue)] }

    public static func restored(from value: Any?) -> GlobalShortcut {
        guard let value = value as? [String: Int],
              let code = value["keyCode"].flatMap(UInt16.init(exactly:)),
              let modifiers = value["modifiers"].flatMap(UInt.init(exactly:)),
              let shortcut = GlobalShortcut(keyCode: code, modifiers: ShortcutModifiers(rawValue: modifiers)) else {
            return .defaultShortcut
        }
        return shortcut
    }

    /// Special keys have stable menu equivalents; printable keys are translated by the app.
    public var fallbackKeyEquivalent: String { Self.keys[keyCode]! }
    public var specialKeyLabel: String? {
        if let label = Self.specialLabels[keyCode] { return label }
        if let index = Self.functionKeys.firstIndex(of: keyCode) { return "F\(index + 1)" }
        return nil
    }

    private static let functionKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
    private static let specialLabels: [UInt16: String] = [49: "空格", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟"]
    private static let keys: [UInt16: String] = {
        var keys: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
            11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
            27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
            36: "\r", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "n", 46: "m", 47: ".", 48: "\t", 49: " ", 50: "`", 51: "\u{8}",
            123: "\u{F702}", 124: "\u{F703}", 125: "\u{F701}", 126: "\u{F700}",
            115: "\u{F729}", 119: "\u{F72B}", 116: "\u{F72C}", 121: "\u{F72D}", 117: "\u{F728}"
        ]
        for (index, code) in functionKeys.enumerated() { keys[code] = String(UnicodeScalar(0xF704 + index)!) }
        return keys
    }()
}
