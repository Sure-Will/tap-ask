using TapAsk.Core;

namespace TapAsk;

internal sealed class ShortcutSettingsForm : Form
{
    private readonly Label shortcutLabel = new() { AutoSize = false, Height = 42, Dock = DockStyle.Top, TextAlign = ContentAlignment.MiddleCenter, Font = new Font(SystemFonts.MessageBoxFont!, FontStyle.Bold) };
    private readonly Label instruction = new() { AutoSize = false, Height = 48, Dock = DockStyle.Top, TextAlign = ContentAlignment.MiddleCenter, Text = "按下新的快捷键，例如 Ctrl+Alt+空格" };
    private readonly Func<GlobalShortcut, bool> save;
    private GlobalShortcut candidate;

    public ShortcutSettingsForm(GlobalShortcut current, Func<GlobalShortcut, bool> save)
    {
        this.save = save;
        candidate = current;
        Text = "快捷键设置";
        ClientSize = new Size(390, 160);
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        ShowInTaskbar = false;
        TopMost = true;
        KeyPreview = true;
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(4) };
        var ok = new Button { Text = "保存", AutoSize = true };
        var cancel = new Button { Text = "取消", DialogResult = DialogResult.Cancel, AutoSize = true };
        var reset = new Button { Text = "恢复默认", AutoSize = true };
        ok.Click += (_, _) => { if (save(candidate)) { DialogResult = DialogResult.OK; Close(); } };
        reset.Click += (_, _) => RecordShortcut(GlobalShortcut.Default);
        buttons.Controls.AddRange([ok, cancel, reset]);
        Controls.Add(shortcutLabel); Controls.Add(instruction); Controls.Add(buttons);
        CancelButton = cancel;
        RecordShortcut(current);
        KeyDown += (_, e) =>
        {
            var modifiers = (e.Control ? ShortcutModifiers.Control : 0) |
                            (e.Alt ? ShortcutModifiers.Alt : 0) | (e.Shift ? ShortcutModifiers.Shift : 0);
            if ((modifiers & (ShortcutModifiers.Control | ShortcutModifiers.Alt)) == 0) return;
            RecordShortcut(new GlobalShortcut((uint)e.KeyCode, modifiers));
            e.Handled = e.SuppressKeyPress = true;
        };
    }

    public void RecordShortcut(GlobalShortcut shortcut)
    {
        var problem = shortcut.ValidationMessage();
        if (problem is not null) { instruction.Text = problem; return; }
        candidate = shortcut;
        shortcutLabel.Text = shortcut.ToString();
        instruction.Text = "按下新的快捷键，例如 Ctrl+Alt+空格";
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        var modifiers = ((keyData & Keys.Control) != 0 ? ShortcutModifiers.Control : 0) |
                        ((keyData & Keys.Alt) != 0 ? ShortcutModifiers.Alt : 0) |
                        ((keyData & Keys.Shift) != 0 ? ShortcutModifiers.Shift : 0);
        if ((modifiers & (ShortcutModifiers.Control | ShortcutModifiers.Alt)) != 0)
        {
            RecordShortcut(new GlobalShortcut((uint)(keyData & Keys.KeyCode), modifiers));
            return true;
        }
        return base.ProcessCmdKey(ref msg, keyData);
    }
}
