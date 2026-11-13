using System.Reflection;
using System.Runtime.ExceptionServices;
using TapAsk;
using TapAsk.Core;
using Xunit;

namespace TapAsk.WindowsTests;

public class SettingsPopupTests
{
    [Fact]
    public void FallbackAnchorFollowsTaskbarEdge()
    {
        var screen = new Rectangle(0, 0, 1920, 1080);
        Assert.Equal(new Point(1920, 1040), SettingsPopup.DefaultAnchor(screen, new Rectangle(0, 0, 1920, 1040)));
        Assert.Equal(new Point(1920, 40), SettingsPopup.DefaultAnchor(screen, new Rectangle(0, 40, 1920, 1040)));
        Assert.Equal(new Point(40, 1080), SettingsPopup.DefaultAnchor(screen, new Rectangle(40, 0, 1880, 1080)));
        Assert.Equal(new Point(1880, 1080), SettingsPopup.DefaultAnchor(screen, new Rectangle(0, 0, 1880, 1080)));
    }

    [Fact]
    public void ShortcutPopupRecordsSavesAndCanBeCancelled()
    {
        OnSta(() =>
        {
            GlobalShortcut? saved = null;
            using var form = new ShortcutSettingsForm(GlobalShortcut.Default, value => { saved = value; return true; });
            using var popup = new SettingsPopup(form);
            popup.ShowAt(Anchor());
            Application.DoEvents();
            Assert.True(popup.Visible);
            Assert.False(form.TopLevel);
            Assert.True(form.ContainsFocus);
            Assert.True(Screen.FromPoint(Anchor()).WorkingArea.Contains(popup.Bounds));
            AssertControlsFit(form);
            var handler = typeof(ShortcutSettingsForm).GetMethod("ProcessCmdKey", BindingFlags.Instance | BindingFlags.NonPublic)!;
            object[] input = [new Message(), Keys.Control | Keys.Alt | Keys.K];
            Assert.True((bool)handler.Invoke(form, input)!);
            var buttons = Assert.Single(form.Controls.OfType<FlowLayoutPanel>()).Controls.OfType<Button>();
            Assert.Single(buttons, button => button.Text == "保存").PerformClick();
            Assert.Equal(new GlobalShortcut((uint)Keys.K, ShortcutModifiers.Control | ShortcutModifiers.Alt), saved);
            Assert.False(popup.Visible);

            bool savedOnCancel = false;
            using var cancelForm = new ShortcutSettingsForm(GlobalShortcut.Default, _ => { savedOnCancel = true; return true; });
            using var cancelPopup = new SettingsPopup(cancelForm);
            cancelPopup.ShowAt(Anchor());
            Application.DoEvents();
            var cancelButtons = Assert.Single(cancelForm.Controls.OfType<FlowLayoutPanel>()).Controls.OfType<Button>();
            Assert.Single(cancelButtons, button => button.Text == "取消").PerformClick();
            Assert.False(cancelPopup.Visible);
            Assert.False(savedOnCancel);
        });
    }

    [Fact]
    public void OrderPopupKeepsKeyboardAndDropReorderingAndDiscardsClosedDraft()
    {
        OnSta(() =>
        {
            Provider[] providers = [new("first", "First", new Uri("https://first.invalid/"), ["first.invalid"]),
                new("second", "Second", new Uri("https://second.invalid/"), ["second.invalid"])];
            Provider[]? saved = null;
            using var form = new ProviderOrderForm(providers, providers);
            form.FormClosed += (_, _) => { if (form.DialogResult == DialogResult.OK) saved = form.OrderedProviders; };
            using var popup = new SettingsPopup(form);
            popup.ShowAt(Anchor());
            Application.DoEvents();
            Assert.True(popup.Visible);
            Assert.False(form.TopLevel);
            AssertControlsFit(form);
            var list = Assert.Single(form.Controls.OfType<ListBox>());
            var onKeyDown = typeof(Control).GetMethod("OnKeyDown", BindingFlags.Instance | BindingFlags.NonPublic)!;
            onKeyDown.Invoke(list, [new KeyEventArgs(Keys.Alt | Keys.Down)]);
            Assert.Equal(providers.Reverse(), form.OrderedProviders);
            onKeyDown.Invoke(list, [new KeyEventArgs(Keys.Alt | Keys.Up)]);
            Assert.Equal(providers, form.OrderedProviders);
            var secondRow = list.GetItemRectangle(1);
            var target = list.PointToScreen(new Point(4, secondRow.Bottom - 1));
            var data = new DataObject();
            data.SetData(typeof(Provider), providers[0]);
            var drop = new DragEventArgs(data, 0, target.X, target.Y, DragDropEffects.Move, DragDropEffects.Move);
            typeof(Control).GetMethod("OnDragDrop", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(list, [drop]);
            Assert.Equal(providers.Reverse(), form.OrderedProviders);
            var buttons = Assert.Single(form.Controls.OfType<FlowLayoutPanel>()).Controls.OfType<Button>();
            Assert.Single(buttons, button => button.Text == "保存").PerformClick();
            Assert.Equal(providers.Reverse(), saved);
            Assert.False(popup.Visible);

            bool savedOnClose = false;
            using var cancelForm = new ProviderOrderForm(providers, providers);
            cancelForm.FormClosed += (_, _) => savedOnClose = cancelForm.DialogResult == DialogResult.OK;
            using var cancelPopup = new SettingsPopup(cancelForm);
            cancelPopup.ShowAt(Anchor());
            Application.DoEvents();
            cancelPopup.Close(ToolStripDropDownCloseReason.AppClicked);
            Assert.False(cancelPopup.Visible);
            Assert.False(savedOnClose);
        });
    }

    private static Point Anchor()
    {
        var work = Screen.PrimaryScreen!.WorkingArea;
        return new Point(work.Right - 20, work.Bottom - 20);
    }

    private static void AssertControlsFit(Form form)
    {
        var buttons = Assert.Single(form.Controls.OfType<FlowLayoutPanel>());
        foreach (Control button in buttons.Controls)
            Assert.True(buttons.ClientRectangle.Contains(button.Bounds), $"Button does not fit: {button.Text}");
        foreach (var label in form.Controls.OfType<Label>())
        {
            var measured = TextRenderer.MeasureText(label.Text, label.Font,
                new Size(label.ClientSize.Width, int.MaxValue), TextFormatFlags.WordBreak);
            Assert.True(measured.Height <= label.ClientSize.Height, $"Label does not fit: {label.Text}");
        }
    }

    private static void OnSta(Action action)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try { action(); }
            catch (Exception ex) { failure = ex; }
        });
        thread.IsBackground = true;
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(10)), "Settings popup interaction did not complete.");
        if (failure is not null) ExceptionDispatchInfo.Capture(failure).Throw();
    }
}
