using System.Text.Json;
using System.Text.Json.Nodes;
using TapAsk.Core;

namespace TapAsk;

internal sealed class SettingsStore
{
    private readonly string path;
    private readonly JsonObject values;

    public SettingsStore(string? settingsPath = null)
    {
        path = settingsPath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TapAsk", "settings.json");
        values = File.Exists(path)
            ? JsonNode.Parse(File.ReadAllText(path))?.AsObject() ?? throw new InvalidDataException("设置文件为空。")
            : new JsonObject();
    }

    public string? GetLastPage(string providerId) => values[$"LastPage.{providerId}"]?.GetValue<string>();
    public string? GetLastProviderId() => values["LastProviderID"]?.GetValue<string>();
    public string[]? GetProviderOrder() => values["ProviderOrder"]?.Deserialize<string[]>();
    public PanelRect? GetPanelFrame() => values["PanelFrame"]?.Deserialize<PanelRect>();
    public GlobalShortcut GetGlobalShortcut()
    {
        var shortcut = values["GlobalShortcut"]?.Deserialize<GlobalShortcut>() ?? GlobalShortcut.Default;
        return shortcut.ValidationMessage() is null ? shortcut : GlobalShortcut.Default;
    }
    public bool AutoUpdateEnabled => values["AutoUpdateEnabled"]?.GetValue<bool>() ?? true;
    public bool AutoStartAttempted => values["AutoStartAttempted"]?.GetValue<bool>() ?? false;
    public DateTimeOffset? LastUpdateCheck => values["LastUpdateCheck"]?.Deserialize<DateTimeOffset>();

    public void SaveLastProviderId(string providerId) => Save("LastProviderID", providerId);
    public void SaveProviderOrder(IEnumerable<string> ids)
    {
        values["ProviderOrder"] = JsonSerializer.SerializeToNode(ids);
        Write();
    }
    public void SavePanelFrame(PanelRect frame)
    {
        if (GetPanelFrame() == frame) return;
        values["PanelFrame"] = JsonSerializer.SerializeToNode(frame);
        Write();
    }
    public void SaveGlobalShortcut(GlobalShortcut shortcut)
    {
        values["GlobalShortcut"] = JsonSerializer.SerializeToNode(shortcut);
        Write();
    }
    public void SaveAutoUpdateEnabled(bool enabled) { values["AutoUpdateEnabled"] = enabled; Write(); }
    public void SaveAutoStartAttempted() { values["AutoStartAttempted"] = true; Write(); }
    public void SaveLastUpdateCheck(DateTimeOffset time) { values["LastUpdateCheck"] = JsonSerializer.SerializeToNode(time); Write(); }

    public void SaveLastPage(string providerId, string value)
    {
        Save($"LastPage.{providerId}", value);
    }

    private void Save(string key, string value)
    {
        if (values[key]?.GetValue<string>() == value) return;
        values[key] = value;
        Write();
    }

    private void Write()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporaryPath = path + ".tmp";
        File.WriteAllText(temporaryPath, values.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporaryPath, path, true);
    }
}
