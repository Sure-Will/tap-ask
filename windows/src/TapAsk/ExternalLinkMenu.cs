using Microsoft.Web.WebView2.Core;
using TapAsk.Core;

namespace TapAsk;

// A context-menu selection identifies an actual link and is explicitly initiated by the user.
internal sealed class ExternalLinkMenu : IDisposable
{
    private readonly CoreWebView2 core;
    private readonly NavigationPolicy policy;
    private readonly Func<bool> isActive;
    private readonly Action<Uri> open;
    private readonly CoreWebView2ContextMenuItem item;
    private (Uri Link, string Page)? pending;

    public ExternalLinkMenu(CoreWebView2 core, NavigationPolicy policy, Func<bool> isActive, Action<Uri> open)
    {
        this.core = core;
        this.policy = policy;
        this.isActive = isActive;
        this.open = open;
        item = core.Environment.CreateContextMenuItem("在默认浏览器中打开", null, CoreWebView2ContextMenuItemKind.Command);
        item.CustomItemSelected += OnSelected;
        core.ContextMenuRequested += OnRequested;
    }

    private void OnRequested(object? sender, CoreWebView2ContextMenuRequestedEventArgs args)
    {
        pending = null;
        if (!isActive()) return;
        var target = args.ContextMenuTarget;
        var link = ExternalLinkContext.BrowserUrl(policy, target.HasLinkUri, target.LinkUri, target.FrameUri);
        if (link is null || string.IsNullOrEmpty(target.PageUri)) return;
        pending = (link, target.PageUri);
        args.MenuItems.Add(item);
    }

    private void OnSelected(object? sender, object args)
    {
        var selected = pending;
        pending = null;
        if (selected is null || !isActive() || !string.Equals(core.Source, selected.Value.Page, StringComparison.Ordinal)) return;
        open(selected.Value.Link);
    }

    public void Dispose()
    {
        core.ContextMenuRequested -= OnRequested;
        item.CustomItemSelected -= OnSelected;
        pending = null;
    }
}
