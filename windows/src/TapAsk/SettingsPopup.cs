namespace TapAsk;

internal sealed class SettingsPopup : ToolStripDropDown
{
    private readonly Form content;

    public SettingsPopup(Form content)
    {
        this.content = content;
        AutoClose = true;
        AutoSize = true;
        Padding = Padding.Empty;
        content.TopMost = false;
        content.TopLevel = false;
        content.FormBorderStyle = FormBorderStyle.None;
        content.ShowInTaskbar = false;
        ScaleContent(content);
        var host = new ToolStripControlHost(content)
        {
            AutoSize = false,
            Size = content.ClientSize,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        Items.Add(host);
        content.FormClosed += (_, _) => Close();
        content.Show();
    }

    private static void ScaleContent(Form form)
    {
        float scale = form.DeviceDpi / 96f;
        if (scale == 1) return;
        form.SuspendLayout();
        form.ClientSize = new Size((int)Math.Round(form.ClientSize.Width * scale),
                                   (int)Math.Round(form.ClientSize.Height * scale));
        foreach (Control control in form.Controls)
        {
            if (control.Dock is DockStyle.Top or DockStyle.Bottom)
                control.Height = (int)Math.Round(control.Height * scale);
            var padding = control.Padding;
            control.Padding = new Padding((int)Math.Round(padding.Left * scale), (int)Math.Round(padding.Top * scale),
                                          (int)Math.Round(padding.Right * scale), (int)Math.Round(padding.Bottom * scale));
        }
        form.ResumeLayout(performLayout: true);
    }

    public void ShowAt(Point anchor)
    {
        Show(anchor, ToolStripDropDownDirection.AboveLeft);
        content.Focus();
    }

    internal static Point DefaultAnchor(Rectangle screen, Rectangle work)
    {
        if (work.Top > screen.Top) return new Point(work.Right, work.Top);
        if (work.Left > screen.Left) return new Point(work.Left, work.Bottom);
        return new Point(work.Right, work.Bottom);
    }
}
