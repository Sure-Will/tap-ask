using System.Drawing.Drawing2D;

namespace TapAsk;

// An owned window is needed to appear above the native WebView2 child window.
internal sealed class InfoOverlayForm(Form owner, bool centered = false, Action? retry = null) : Form
{
    private readonly Label message = new() { AutoEllipsis = true, ForeColor = Color.White, TextAlign = ContentAlignment.MiddleCenter };
    private readonly Button retryButton = new() { Text = "重试", AutoSize = false, Visible = false };
    private int topOffset;
    private bool allowRetry;

    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams
    {
        get { var value = base.CreateParams; value.ExStyle |= 0x80 | 0x08000000; return value; }
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == 0x0084 && !allowRetry) { message.Result = new IntPtr(-1); return; }
        base.WndProc(ref message);
    }

    public void SetContent(string text, bool show, int offset = 28, bool canRetry = false)
    {
        if (IsDisposed) return;
        topOffset = offset;
        message.Text = text;
        allowRetry = canRetry;
        retryButton.Visible = canRetry;
        if (!show || !owner.Visible) { Hide(); return; }
        UpdatePosition();
        if (!Visible) Show(owner);
    }

    public void InitializeOverlay()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.FromArgb(45, 45, 45);
        message.BackColor = BackColor;
        retryButton.Click += (_, _) => retry?.Invoke();
        Controls.Add(message);
        Controls.Add(retryButton);
    }

    public void UpdatePosition()
    {
        if (!owner.Visible) return;
        float scale = owner.DeviceDpi / 96f;
        int height = (int)Math.Round(38 * scale);
        int maxWidth = Math.Max(height, owner.ClientSize.Width - (int)Math.Round(32 * scale));
        int textWidth = TextRenderer.MeasureText(message.Text, message.Font).Width;
        int width = Math.Clamp(textWidth + (int)Math.Round((allowRetry ? 96 : 28) * scale), height, maxWidth);
        int y = centered ? (owner.ClientSize.Height - height) / 2 : (int)Math.Round(topOffset * scale);
        var position = owner.PointToScreen(new Point((owner.ClientSize.Width - width) / 2, y));
        Bounds = new Rectangle(position, new Size(width, height));
        int buttonWidth = allowRetry ? (int)Math.Round(60 * scale) : 0;
        retryButton.Bounds = new Rectangle(width - buttonWidth - (int)(5 * scale), (int)(4 * scale), buttonWidth, height - (int)(8 * scale));
        message.Bounds = new Rectangle((int)(8 * scale), 0, width - buttonWidth - (int)(16 * scale), height);
        using var path = new GraphicsPath();
        int diameter = Math.Min(height, (int)Math.Round(16 * scale));
        var rect = new Rectangle(0, 0, width, height);
        path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
        path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
        path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        var previousRegion = Region;
        Region = new Region(path);
        previousRegion?.Dispose();
    }
}
