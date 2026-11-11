using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class GlobalShortcutTests
{
    [Fact] public void DefaultIsAltSpace() => Assert.Null(GlobalShortcut.Default.ValidationMessage());
    [Fact] public void RequiresControlOrAlt() => Assert.NotNull(new GlobalShortcut(0x41, ShortcutModifiers.Shift).ValidationMessage());
    [Fact] public void RejectsTapAskAndEditingShortcuts() => Assert.NotNull(new GlobalShortcut(0x52, ShortcutModifiers.Control).ValidationMessage());
    [Fact] public void AcceptsUnreservedCombination() => Assert.Null(new GlobalShortcut(0x4B, ShortcutModifiers.Control | ShortcutModifiers.Alt).ValidationMessage());
}
