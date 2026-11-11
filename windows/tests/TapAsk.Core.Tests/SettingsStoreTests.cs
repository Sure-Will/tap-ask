using System.Text.Json.Nodes;
using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class SettingsStoreTests
{
    [Fact]
    public void FirstLaunchSavesDefaultWithoutLosingExistingSettings()
    {
        WithSettings("""{"LastPage.chatgpt":"https://chatgpt.com/c/example","otherSetting":{"value":42}}""", path =>
        {
            var catalog = ProviderCatalog.Load(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "providers.json")));
            var settings = new global::TapAsk.SettingsStore(path);
            var selected = ProviderSelection.Restored(catalog.Providers, settings.GetLastProviderId());
            settings.SaveLastProviderId(selected!.Id);

            var restored = new global::TapAsk.SettingsStore(path);
            Assert.Equal("deepseek", restored.GetLastProviderId());
            Assert.Equal("https://chatgpt.com/c/example", restored.GetLastPage("chatgpt"));
            Assert.Equal(42, JsonNode.Parse(File.ReadAllText(path))!["otherSetting"]!["value"]!.GetValue<int>());
        });
    }

    [Fact]
    public void ExistingProviderChoiceSurvivesRestart()
    {
        WithSettings("""{"LastProviderID":"chatgpt"}""", path =>
        {
            var catalog = ProviderCatalog.Load(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "providers.json")));
            var settings = new global::TapAsk.SettingsStore(path);
            var selected = ProviderSelection.Restored(catalog.Providers, settings.GetLastProviderId());
            settings.SaveLastProviderId(selected!.Id);
            Assert.Equal("chatgpt", new global::TapAsk.SettingsStore(path).GetLastProviderId());
        });
    }

    [Fact]
    public void OrderFrameAndShortcutSurviveRestartWithoutChangingOtherSettings()
    {
        WithSettings("""{"LastProviderID":"deepseek"}""", path =>
        {
            var settings = new global::TapAsk.SettingsStore(path);
            var frame = new PanelRect(120, 80, 480, 720);
            var shortcut = new GlobalShortcut(0x4B, ShortcutModifiers.Control | ShortcutModifiers.Alt);
            settings.SaveProviderOrder(["grok", "deepseek"]);
            settings.SavePanelFrame(frame);
            settings.SaveGlobalShortcut(shortcut);
            var restored = new global::TapAsk.SettingsStore(path);
            Assert.Equal(new[] { "grok", "deepseek" }, restored.GetProviderOrder());
            Assert.Equal(frame, restored.GetPanelFrame());
            Assert.Equal(shortcut, restored.GetGlobalShortcut());
            Assert.Equal("deepseek", restored.GetLastProviderId());
        });
    }

    private static void WithSettings(string json, Action<string> action)
    {
        var directory = Path.Combine(Path.GetTempPath(), $"TapAsk.Tests.{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "settings.json");
        try { File.WriteAllText(path, json); action(path); }
        finally { File.Delete(path); Directory.Delete(directory); }
    }
}
