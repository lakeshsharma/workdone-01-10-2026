namespace AgentRecovery;

public sealed class AgentEditorForm : Form
{
    private readonly TextBox nodeName = new(), host = new(), sshUser = new(), password = new() { UseSystemPasswordChar = true };
    private readonly TextBox workspaceRoot = new(), protectedPaths = new() { Multiline = true, ScrollBars = ScrollBars.Vertical };
    private readonly NumericUpDown port = new() { Minimum = 1, Maximum = 65535, Value = 22 };

    public AgentProfile Result { get; private set; }

    public AgentEditorForm(AgentProfile original)
    {
        Result = new AgentProfile
        {
            Name = original.Name, Host = original.Host, Port = original.Port,
            Username = original.Username, Password = original.Password,
            WorkspaceRoot = original.WorkspaceRoot, HostKeySha256 = original.HostKeySha256,
            ProtectedPaths = original.ProtectedPaths, CredentialGroup = original.CredentialGroup
        };
        Text = original.Name.Length == 0 ? "Add Linux agent" : "Edit Linux agent";
        Width = 760; Height = 690; MinimumSize = new Size(660, 610);
        StartPosition = FormStartPosition.CenterParent;
        Font = new Font("Segoe UI", 9.5f);

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 8, Padding = new Padding(16) };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 185));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        AddRow(layout, 0, "Jenkins agent name", nodeName);
        AddRow(layout, 1, "SSH host or IP", host);
        AddRow(layout, 2, "SSH port", port);
        AddRow(layout, 3, "SSH username", sshUser);
        AddRow(layout, 4, "SSH password", password);
        AddRow(layout, 5, "Workspace root", workspaceRoot);
        protectedPaths.Height = 90;
        AddRow(layout, 6, "Protected paths (optional)", protectedPaths);
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        var help = new Label { Dock = DockStyle.Bottom, Height = 95, Padding = new Padding(18, 5, 18, 5), Text =
            "Workspace root: the parent folder that holds this agent's Jenkins job workspaces, such as /home/jenkins/workspace. " +
            "The tool only browses and cleans below this folder.\r\n\r\n" +
            "Protected paths: optional absolute folders inside that root that this tool must never delete. " +
            "Separate multiple paths with semicolons." };
        var tips = new ToolTip();
        tips.SetToolTip(workspaceRoot, "Parent directory containing Jenkins job workspaces on this Linux agent.");
        tips.SetToolTip(protectedPaths, "Optional absolute paths that must never be deleted, separated by semicolons.");

        var footer = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 58, FlowDirection = FlowDirection.RightToLeft };
        var save = new Button { Text = "Save agent", AutoSize = true, Margin = new Padding(8) };
        save.Click += (_, _) => SaveAgent();
        var cancel = new Button { Text = "Cancel", AutoSize = true, DialogResult = DialogResult.Cancel, Margin = new Padding(8) };
        var showPassword = new CheckBox { Text = "Show SSH password", AutoSize = true, Margin = new Padding(8, 13, 20, 0) };
        showPassword.CheckedChanged += (_, _) => password.UseSystemPasswordChar = !showPassword.Checked;
        var resetTrust = new Button { Text = "Reset SSH trust", AutoSize = true, Margin = new Padding(8) };
        resetTrust.Click += (_, _) =>
        {
            if (MessageBox.Show(this,
                "Forget this agent's saved SSH identity? The next connection will ask you to trust the new identity. Use this only after the agent was intentionally rebuilt or its SSH key changed.",
                "Reset SSH trust", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
            {
                Result.HostKeySha256 = "";
                MessageBox.Show(this, "Saved SSH identity will be forgotten when you save this agent.");
            }
        };
        footer.Controls.Add(save); footer.Controls.Add(cancel); footer.Controls.Add(showPassword);
        footer.Controls.Add(resetTrust);
        Controls.Add(layout); Controls.Add(help); Controls.Add(footer);
        AcceptButton = save; CancelButton = cancel;

        nodeName.Text = original.Name; host.Text = original.Host; port.Value = Math.Clamp(original.Port, 1, 65535);
        sshUser.Text = original.Username; password.Text = original.Password;
        workspaceRoot.Text = original.WorkspaceRoot;
        protectedPaths.Text = original.ProtectedPaths;
        AppTheme.Apply(this);
        Controls.Add(AppTheme.CreateBanner(Text, "SSH access and workspace safeguards for this Jenkins agent"));
    }

    private static void AddRow(TableLayoutPanel layout, int row, string label, Control field)
    {
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(new Label { Text = label, AutoSize = true, Margin = new Padding(3, 9, 3, 3) }, 0, row);
        field.Dock = DockStyle.Top;
        field.Margin = new Padding(3, 3, 3, 8);
        layout.Controls.Add(field, 1, row);
    }

    private void SaveAgent()
    {
        string name = nodeName.Text.Trim(), sshHost = host.Text.Trim(), user = sshUser.Text.Trim();
        string root = workspaceRoot.Text.Trim(), paths = protectedPaths.Text.Trim();
        if (name.Length == 0 || sshHost.Length == 0 || user.Length == 0)
        { MessageBox.Show("Enter the Jenkins agent name, SSH host, and SSH username."); return; }
        if (root.Length > 0 && (!root.StartsWith('/') || root.TrimEnd('/').Length == 0))
        { MessageBox.Show("Workspace root must be a specific absolute Linux path, not /."); return; }
        if (paths.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Any(path => !path.StartsWith('/')))
        { MessageBox.Show("Every protected path must be absolute."); return; }
        string? originalName = SuggestedAgents.OriginalNameForIp(sshHost);
        if (originalName is not null && !originalName.Equals(name, StringComparison.OrdinalIgnoreCase) &&
            MessageBox.Show(this,
                $"You previously supplied {sshHost} for {originalName}, but this agent is named {name}. Verify the IP and Jenkins node name. Save this mapping anyway?",
                "Check agent mapping", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
            return;
        Result.Name = name; Result.Host = sshHost; Result.Port = (int)port.Value;
        Result.Username = user; Result.Password = password.Text;
        Result.WorkspaceRoot = root; Result.ProtectedPaths = paths;
        DialogResult = DialogResult.OK;
        Close();
    }
}
