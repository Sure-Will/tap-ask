using TapAsk.Core;

namespace TapAsk;

internal sealed class ProviderOrderForm : Form
{
    private readonly Provider[] defaults;
    private readonly ListBox list = new() { Dock = DockStyle.Fill, AllowDrop = true, IntegralHeight = false };
    private Point dragStart;

    public Provider[] OrderedProviders => list.Items.Cast<Provider>().ToArray();

    public ProviderOrderForm(Provider[] defaults, Provider[] ordered)
    {
        this.defaults = defaults;
        Text = "服务商排序";
        ClientSize = new Size(360, 330);
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MinimizeBox = MaximizeBox = false;
        ShowInTaskbar = false;
        TopMost = true;
        list.DisplayMember = nameof(Provider.Name);
        list.Items.AddRange(ordered);
        var help = new Label { Dock = DockStyle.Top, Height = 36, Text = "拖动调整顺序，也可用 Alt+↑ / Alt+↓", TextAlign = ContentAlignment.MiddleLeft, Padding = new Padding(8, 0, 0, 0) };
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(4) };
        var ok = new Button { Text = "保存", DialogResult = DialogResult.OK, AutoSize = true };
        var cancel = new Button { Text = "取消", DialogResult = DialogResult.Cancel, AutoSize = true };
        var reset = new Button { Text = "恢复默认", AutoSize = true };
        ok.Click += (_, _) => { DialogResult = DialogResult.OK; Close(); };
        cancel.Click += (_, _) => { DialogResult = DialogResult.Cancel; Close(); };
        reset.Click += (_, _) => { list.Items.Clear(); list.Items.AddRange(this.defaults); list.SelectedIndex = 0; };
        buttons.Controls.AddRange([ok, cancel, reset]);
        Controls.Add(list); Controls.Add(help); Controls.Add(buttons);
        AcceptButton = ok; CancelButton = cancel;
        list.KeyDown += (_, e) =>
        {
            if (e.Alt && e.KeyCode is Keys.Up or Keys.Down && list.SelectedIndex >= 0)
            {
                int index = list.SelectedIndex;
                int target = Math.Clamp(index + (e.KeyCode == Keys.Up ? -1 : 1), 0, list.Items.Count - 1);
                MoveItem(index, target > index ? target + 1 : target);
                e.Handled = e.SuppressKeyPress = true;
            }
        };
        list.MouseDown += (_, e) => { dragStart = e.Location; int index = list.IndexFromPoint(e.Location); if (index >= 0) list.SelectedIndex = index; };
        list.MouseMove += (_, e) =>
        {
            if (e.Button == MouseButtons.Left && list.SelectedIndex >= 0 &&
                (Math.Abs(e.X - dragStart.X) > SystemInformation.DragSize.Width / 2 || Math.Abs(e.Y - dragStart.Y) > SystemInformation.DragSize.Height / 2))
                list.DoDragDrop(list.SelectedItem!, DragDropEffects.Move);
        };
        list.DragOver += (_, e) => e.Effect = e.Data?.GetDataPresent(typeof(Provider)) == true ? DragDropEffects.Move : DragDropEffects.None;
        list.DragDrop += (_, e) =>
        {
            if (e.Data?.GetData(typeof(Provider)) is not Provider dragged) return;
            int from = list.Items.IndexOf(dragged);
            var point = list.PointToClient(new Point(e.X, e.Y));
            int to = list.IndexFromPoint(point);
            if (to < 0) to = list.Items.Count;
            else if (point.Y > list.GetItemRectangle(to).Top + list.ItemHeight / 2) to++;
            MoveItem(from, to);
        };
        if (list.Items.Count > 0) list.SelectedIndex = 0;
    }

    private void MoveItem(int from, int to)
    {
        if (from < 0) return;
        var ids = ProviderOrder.Moving(OrderedProviders.Select(p => p.Id).ToArray(), from, to);
        var ordered = ProviderOrder.Ordered(OrderedProviders, ids);
        var selected = ordered.First(p => p.Id == ids[to > from ? to - 1 : to]);
        list.Items.Clear(); list.Items.AddRange(ordered); list.SelectedItem = selected;
    }
}
