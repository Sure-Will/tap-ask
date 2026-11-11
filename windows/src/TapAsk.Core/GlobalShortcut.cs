namespace TapAsk.Core;

[Flags]
public enum ShortcutModifiers : uint { Alt = 1, Control = 2, Shift = 4 }

public readonly record struct GlobalShortcut(uint Key, ShortcutModifiers Modifiers)
{
    public static GlobalShortcut Default => new(0x20, ShortcutModifiers.Alt);

    public string? ValidationMessage()
    {
        if ((Modifiers & ~(ShortcutModifiers.Alt | ShortcutModifiers.Control | ShortcutModifiers.Shift)) != 0 ||
            (Modifiers & (ShortcutModifiers.Alt | ShortcutModifiers.Control)) == 0)
            return "请按住 Ctrl 或 Alt，可以加上 Shift。";
        bool supported = Key is >= 0x30 and <= 0x5A or >= 0x70 and <= 0x87 or
            >= 0xBA and <= 0xC0 or >= 0xDB and <= 0xDE or 0x20 or >= 0x21 and <= 0x28;
        if (!supported) return "请选择字母、数字、标点、空格、方向键或功能键。";
        if ((Modifiers == ShortcutModifiers.Alt && Key is 0x09 or 0x73) ||
            (Modifiers == ShortcutModifiers.Control && (Key is 0x41 or 0x43 or 0x52 or 0x56 or 0x58 or 0x5A or >= 0x31 and <= 0x36 or 0xBC)) ||
            (Modifiers == (ShortcutModifiers.Control | ShortcutModifiers.Shift) && Key == 0x5A))
            return "这组快捷键已用于其他操作，请换一组。";
        return null;
    }

    public override string ToString()
    {
        var parts = new List<string>();
        if (Modifiers.HasFlag(ShortcutModifiers.Control)) parts.Add("Ctrl");
        if (Modifiers.HasFlag(ShortcutModifiers.Alt)) parts.Add("Alt");
        if (Modifiers.HasFlag(ShortcutModifiers.Shift)) parts.Add("Shift");
        parts.Add(Key switch
        {
            0x20 => "空格", 0x25 => "←", 0x26 => "↑", 0x27 => "→", 0x28 => "↓",
            >= 0x70 and <= 0x87 => $"F{Key - 0x6F}",
            >= 0x30 and <= 0x5A => ((char)Key).ToString(),
            _ => $"键 {Key:X2}"
        });
        return string.Join("+", parts);
    }
}
