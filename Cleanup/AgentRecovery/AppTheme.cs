using System.Drawing.Drawing2D;

namespace AgentRecovery;

internal static class AppTheme
{
    public static readonly Color Canvas = Color.FromArgb(245, 247, 251);
    public static readonly Color Surface = Color.White;
    public static readonly Color Ink = Color.FromArgb(27, 39, 58);
    public static readonly Color Muted = Color.FromArgb(100, 116, 139);
    public static readonly Color Border = Color.FromArgb(221, 228, 237);
    public static readonly Color Accent = Color.FromArgb(70, 75, 199);
    public static readonly Color AccentSoft = Color.FromArgb(235, 236, 252);
    public static readonly Color Danger = Color.FromArgb(187, 47, 64);
    public static readonly Color Header = Color.FromArgb(25, 35, 57);
    public static readonly Font StatusFont = new("Segoe UI Semibold", 9f);

    public static void Apply(Form form)
    {
        form.BackColor = Canvas;
        form.ForeColor = Ink;
        form.Font = new Font("Segoe UI", 9.5f);
        form.AutoScaleMode = AutoScaleMode.Dpi;
        foreach (Control child in form.Controls) ApplyControl(child);
    }

    public static Panel CreateBanner(string title, string subtitle)
    {
        var banner = new Panel { Dock = DockStyle.Top, Height = 76, BackColor = Header };
        banner.Controls.Add(new Label { Text = title, AutoSize = true, Location = new Point(23, 12),
            Font = new Font("Segoe UI Semibold", 17f), ForeColor = Color.White, BackColor = Color.Transparent });
        banner.Controls.Add(new Label { Text = subtitle, AutoSize = true, Location = new Point(25, 46),
            Font = new Font("Segoe UI", 9f), ForeColor = Color.FromArgb(191, 202, 220), BackColor = Color.Transparent });
        banner.Paint += (_, e) =>
        {
            using var stripe = new SolidBrush(Accent);
            e.Graphics.FillRectangle(stripe, 0, 0, 5, banner.Height);
        };
        return banner;
    }

    private static void ApplyControl(Control control)
    {
        switch (control)
        {
            case TabControl tabs:
                tabs.DrawMode = TabDrawMode.OwnerDrawFixed;
                tabs.SizeMode = TabSizeMode.Fixed;
                tabs.ItemSize = new Size(155, 42);
                tabs.DrawItem += DrawTab;
                tabs.BackColor = Canvas;
                break;
            case TabPage page:
                page.BackColor = Surface;
                page.Padding = new Padding(10);
                break;
            case DataGridView grid:
                StyleGrid(grid);
                break;
            case TreeView tree:
                tree.BackColor = Surface;
                tree.ForeColor = Ink;
                tree.BorderStyle = BorderStyle.None;
                tree.ShowLines = false;
                tree.ItemHeight = 30;
                tree.Font = new Font("Segoe UI", 10f);
                break;
            case RichTextBox:
                break;
            case TextBox field:
                field.BorderStyle = BorderStyle.FixedSingle;
                field.ForeColor = Ink;
                field.BackColor = field.ReadOnly ? Canvas : Surface;
                if (field.Multiline) field.Font = new Font("Segoe UI", 9.5f);
                break;
            case NumericUpDown number:
                number.BackColor = Surface;
                number.ForeColor = Ink;
                number.BorderStyle = BorderStyle.FixedSingle;
                break;
            case Button button:
                StyleButton(button);
                break;
            case StatusStrip strip:
                strip.BackColor = Surface;
                strip.ForeColor = Muted;
                strip.Padding = new Padding(12, 2, 8, 2);
                strip.SizingGrip = false;
                break;
            case Label label:
                label.ForeColor = label.Text.StartsWith("Workspace root:", StringComparison.Ordinal) ||
                    label.Text.StartsWith("Double-click", StringComparison.Ordinal) ? Muted : Ink;
                break;
            case SplitContainer split:
                split.BackColor = Border;
                split.Panel1.BackColor = Surface;
                split.Panel2.BackColor = Surface;
                split.SplitterWidth = 6;
                break;
            case Panel panel:
                panel.BackColor = Surface;
                break;
        }
        if (control is FlowLayoutPanel flow) flow.BackColor = Surface;
        if (control is TableLayoutPanel table) table.BackColor = Surface;
        foreach (Control child in control.Controls) ApplyControl(child);
    }

    private static void StyleGrid(DataGridView grid)
    {
        grid.BackgroundColor = Surface;
        grid.BorderStyle = BorderStyle.None;
        grid.GridColor = Border;
        grid.CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal;
        grid.RowHeadersVisible = false;
        grid.EnableHeadersVisualStyles = false;
        grid.ColumnHeadersBorderStyle = DataGridViewHeaderBorderStyle.None;
        grid.ColumnHeadersHeight = 42;
        grid.ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.DisableResizing;
        grid.ColumnHeadersDefaultCellStyle.BackColor = Color.FromArgb(237, 241, 247);
        grid.ColumnHeadersDefaultCellStyle.ForeColor = Muted;
        grid.ColumnHeadersDefaultCellStyle.Font = new Font("Segoe UI Semibold", 9.5f);
        grid.ColumnHeadersDefaultCellStyle.Padding = new Padding(8, 0, 4, 0);
        grid.DefaultCellStyle.BackColor = Surface;
        grid.DefaultCellStyle.ForeColor = Ink;
        grid.DefaultCellStyle.SelectionBackColor = AccentSoft;
        grid.DefaultCellStyle.SelectionForeColor = Ink;
        grid.DefaultCellStyle.Padding = new Padding(8, 2, 4, 2);
        grid.AlternatingRowsDefaultCellStyle.BackColor = Color.FromArgb(250, 251, 254);
        grid.AlternatingRowsDefaultCellStyle.SelectionBackColor = AccentSoft;
        grid.RowTemplate.Height = 38;
        foreach (DataGridViewRow row in grid.Rows) row.Height = 38;
    }

    private static void StyleButton(Button button)
    {
        bool danger = button.Text.StartsWith("Delete", StringComparison.OrdinalIgnoreCase) ||
            button.Text.StartsWith("Remove", StringComparison.OrdinalIgnoreCase);
        bool primary = button.Text.StartsWith("Scan", StringComparison.OrdinalIgnoreCase) ||
            button.Text.StartsWith("Review checked", StringComparison.OrdinalIgnoreCase) ||
            button.Text.StartsWith("Save", StringComparison.OrdinalIgnoreCase) ||
            button.Text.StartsWith("Connect", StringComparison.OrdinalIgnoreCase);
        Color fill = danger ? Danger : primary ? Accent : Color.FromArgb(240, 243, 249);
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = 0;
        button.FlatAppearance.MouseOverBackColor = danger ? Color.FromArgb(161, 36, 54) :
            primary ? Color.FromArgb(55, 59, 170) : Color.FromArgb(225, 231, 242);
        button.FlatAppearance.MouseDownBackColor = button.FlatAppearance.MouseOverBackColor;
        button.BackColor = fill;
        button.ForeColor = danger || primary ? Color.White : Ink;
        button.Font = new Font("Segoe UI Semibold", 9f);
        button.Cursor = Cursors.Hand;
        button.Padding = new Padding(12, 5, 12, 5);
        button.MinimumSize = new Size(0, 34);
        button.SizeChanged += (_, _) => RoundButton(button);
        RoundButton(button);
    }

    private static void RoundButton(Button button)
    {
        if (button.Width < 12 || button.Height < 12) return;
        using var path = new GraphicsPath();
        int radius = 8, diameter = radius * 2;
        var bounds = new Rectangle(0, 0, button.Width - 1, button.Height - 1);
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        Region? old = button.Region;
        button.Region = new Region(path);
        old?.Dispose();
    }

    private static void DrawTab(object? sender, DrawItemEventArgs e)
    {
        if (sender is not TabControl tabs) return;
        bool active = e.Index == tabs.SelectedIndex;
        Rectangle rect = tabs.GetTabRect(e.Index);
        using var background = new SolidBrush(active ? Surface : Canvas);
        e.Graphics.FillRectangle(background, rect);
        using var font = new Font("Segoe UI Semibold", 9.5f);
        TextRenderer.DrawText(e.Graphics, tabs.TabPages[e.Index].Text,
            font, rect, active ? Accent : Muted,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        if (active)
        {
            using var line = new SolidBrush(Accent);
            e.Graphics.FillRectangle(line, rect.Left + 12, rect.Bottom - 4, rect.Width - 24, 3);
        }
    }
}
