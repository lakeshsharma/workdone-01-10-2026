using System.ComponentModel;
using System.Text.Json.Nodes;

namespace AgentRecovery;

public sealed class MainForm : Form
{
    private readonly LinuxProbe probe = new();
    private AppSettings settings;
    private BindingList<AgentProfile> agents;
    private readonly TabControl tabs = new() { Dock = DockStyle.Fill };
    private readonly DataGridView dashboard = new() { Dock = DockStyle.Fill, ReadOnly = true, AllowUserToAddRows = false, SelectionMode = DataGridViewSelectionMode.FullRowSelect, MultiSelect = false, AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill };
    private readonly TextBox scanDetails = new() { Dock = DockStyle.Bottom, Height = 175, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical };
    private readonly TreeView tree = new() { Dock = DockStyle.Fill, HideSelection = false, CheckBoxes = true };
    private readonly TextBox folderDetails = new() { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical };
    private readonly Label location = new() { AutoSize = true, Padding = new Padding(7) };
    private readonly Label status = new() { Dock = DockStyle.Bottom, Height = 26, Text = "Ready", Padding = new Padding(8, 4, 0, 0) };
    private readonly StatusStrip connectionBar = new();
    private readonly ToolStripStatusLabel connectionLabel = new() { Spring = true, TextAlign = ContentAlignment.MiddleLeft };
    private readonly RichTextBox liveLog = new() { Dock = DockStyle.Fill, ReadOnly = true, WordWrap = false,
        Font = new Font("Consolas", 9f), BackColor = Color.FromArgb(24, 31, 42), ForeColor = Color.Gainsboro,
        BorderStyle = BorderStyle.None, ScrollBars = RichTextBoxScrollBars.Both };
    private readonly TextBox jenkinsUrl = new(), jenkinsUser = new(), jenkinsToken = new() { UseSystemPasswordChar = true };
    private readonly DataGridView agentGrid = new() { Dock = DockStyle.Fill, AutoGenerateColumns = false, AllowUserToAddRows = false, ReadOnly = true, SelectionMode = DataGridViewSelectionMode.FullRowSelect, MultiSelect = false, AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill };
    private AgentProfile? currentAgent;
    private bool busy;

    public MainForm()
    {
        Text = "Jenkins Agent Recovery";
        Width = 1360; Height = 900; MinimumSize = new Size(960, 680);
        Font = new Font("Segoe UI", 9.5f);
        try { settings = LocalStore.Load(); }
        catch (Exception exc) { settings = new(); MessageBox.Show("Could not load saved settings: " + exc.Message); }
        settings.MigrateLegacyCredentials();
        if (settings.SuggestedAgentsVersion < 1)
        {
            SuggestedAgents.AddMissing(settings.Agents);
            settings.SuggestedAgentsVersion = 1;
        }
        agents = new BindingList<AgentProfile>(settings.Agents);
        probe.ConnectionChanged += OnConnectionChanged;
        connectionBar.Items.Add(connectionLabel);
        Controls.Add(tabs); BuildLiveLog(); Controls.Add(status); Controls.Add(connectionBar);
        BuildDashboard(); BuildExplorer(); BuildSettings();
        tabs.SelectedIndexChanged += (_, _) => UpdateConnectionDisplay();
        FillSettings();
        PopulateDashboardPlaceholders();
        UpdateConnectionDisplay();
        AppTheme.Apply(this);
        Controls.Add(AppTheme.CreateBanner("Jenkins Agent Recovery", "Diagnose disk pressure  •  Review workspace folders  •  Approve cleanup"));
        Log($"Ready. {agents.Count} agents configured; open Settings to complete missing details.");
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        probe.DisconnectAll();
        base.OnFormClosed(e);
    }

    private void OnConnectionChanged(AgentProfile agent, bool connected)
    {
        if (IsDisposed || Disposing) return;
        if (InvokeRequired) { BeginInvoke(new Action<AgentProfile, bool>(OnConnectionChanged), agent, connected); return; }
        UpdateConnectionDisplay();
        Log($"{agent.Name}: SSH {(connected ? "connected" : "disconnected")}.");
    }

    private AgentProfile? StatusAgent() => tabs.SelectedIndex switch
    {
        1 => currentAgent,
        2 => agentGrid.CurrentRow?.DataBoundItem as AgentProfile,
        _ => dashboard.CurrentRow?.Tag as AgentProfile
    };

    private void UpdateConnectionDisplay()
    {
        if (IsDisposed) return;
        foreach (DataGridViewRow row in dashboard.Rows)
            if (row.Tag is AgentProfile agent) row.Cells[1].Value = probe.IsConnected(agent) ? "Connected" : "Disconnected";
        agentGrid.Invalidate();
        var selected = StatusAgent();
        connectionLabel.Text = selected is null ? "SSH: no agent selected" :
            $"{selected.Name} — SSH: {(probe.IsConnected(selected) ? "Connected" : "Disconnected")}";
        connectionLabel.ForeColor = selected is not null && probe.IsConnected(selected) ? Color.DarkGreen : Color.DarkRed;
    }

    private void SetRightClickSelection(DataGridView grid, DataGridViewCellMouseEventArgs e)
    {
        if (e.Button == MouseButtons.Right && e.RowIndex >= 0 && e.ColumnIndex >= 0)
            grid.CurrentCell = grid.Rows[e.RowIndex].Cells[e.ColumnIndex];
    }

    private void AddConnectionMenu(DataGridView grid)
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("Connect now", null, async (_, _) => await ConnectSelected(grid));
        menu.Items.Add("Disconnect", null, async (_, _) => await DisconnectSelected(grid));
        if (ReferenceEquals(grid, dashboard))
            menu.Items.Add("Explore workspace", null, async (_, _) => await ExploreSelected());
        grid.ContextMenuStrip = menu;
        grid.CellMouseDown += (_, e) => SetRightClickSelection(grid, e);
        grid.SelectionChanged += (_, _) => UpdateConnectionDisplay();
    }

    private AgentProfile? AgentFromGrid(DataGridView grid) => ReferenceEquals(grid, dashboard)
        ? grid.CurrentRow?.Tag as AgentProfile : grid.CurrentRow?.DataBoundItem as AgentProfile;

    private async Task ConnectSelected(DataGridView grid)
    {
        var agent = AgentFromGrid(grid);
        if (agent is null) { MessageBox.Show("Select an agent first."); return; }
        if (!SaveSettings()) return;
        try
        {
            status.Text = $"Connecting to {agent.Name}…";
            Log($"{agent.Name}: connecting to {agent.Host}:{agent.Port}.");
            status.Text = await probe.ConnectNowAsync(settings, agent, ConfirmNewHostKey);
            UpdateConnectionDisplay();
        }
        catch (Exception exc)
        {
            status.Text = $"Could not connect to {agent.Name}";
            UpdateConnectionDisplay();
            Log($"{agent.Name}: SSH connection failed: {exc.Message}");
            MessageBox.Show(this, exc.Message, "SSH connection", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private async Task DisconnectSelected(DataGridView grid)
    {
        var agent = AgentFromGrid(grid);
        if (agent is null) { MessageBox.Show("Select an agent first."); return; }
        await probe.DisconnectAsync(agent);
        status.Text = $"Disconnected from {agent.Name}";
        UpdateConnectionDisplay();
    }

    private void BuildLiveLog()
    {
        var panel = new Panel { Dock = DockStyle.Bottom, Height = 184, Padding = new Padding(12, 4, 12, 8) };
        var header = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 37 };
        header.Controls.Add(new Label { Text = "LIVE RUN LOG", AutoSize = true, Margin = new Padding(5, 9, 18, 0), Font = new Font("Segoe UI Semibold", 9f) });
        var clear = new Button { Text = "Clear", Width = 56, Height = 25, Margin = new Padding(3, 1, 3, 0) };
        clear.Click += (_, _) => liveLog.Clear();
        var copy = new Button { Text = "Copy", Width = 56, Height = 25, Margin = new Padding(3, 1, 3, 0) };
        copy.Click += (_, _) => { if (liveLog.TextLength > 0) Clipboard.SetText(liveLog.Text); };
        header.Controls.Add(clear); header.Controls.Add(copy);
        panel.Controls.Add(liveLog); panel.Controls.Add(header);
        Controls.Add(panel);
    }

    private void Log(string message)
    {
        if (IsDisposed) return;
        if (InvokeRequired)
        {
            BeginInvoke(new Action<string>(Log), message);
            return;
        }
        if (liveLog.TextLength > 120_000)
            liveLog.Text = liveLog.Text[^80_000..];
        liveLog.AppendText($"[{DateTime.Now:HH:mm:ss}] {message}{Environment.NewLine}");
        liveLog.SelectionStart = liveLog.TextLength;
        liveLog.ScrollToCaret();
    }

    private static Button ActionButton(string text, EventHandler action)
    {
        var button = new Button { Text = text, AutoSize = true, Height = 38, Margin = new Padding(5, 6, 5, 6) };
        button.Click += action;
        return button;
    }

    private void BuildDashboard()
    {
        var tab = new TabPage("Diagnose"); tabs.TabPages.Add(tab);
        var actions = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 58, Padding = new Padding(8, 3, 0, 0), WrapContents = false, AutoScroll = true };
        actions.Controls.Add(ActionButton("Scan all agents", async (_, _) => await ScanAll()));
        actions.Controls.Add(ActionButton("Explore selected", async (_, _) => await ExploreSelected()));
        actions.Controls.Add(ActionButton("Pause selected agent", async (_, _) => await PauseSelected()));
        actions.Controls.Add(ActionButton("Resume selected agent", async (_, _) => await ResumeSelected()));
        tab.Controls.Add(dashboard); tab.Controls.Add(scanDetails); tab.Controls.Add(actions);
        foreach (var (title, width) in new[] { ("Agent", 130), ("SSH", 105), ("Jenkins", 170), ("Disk free", 120), ("Inodes free", 100), ("Largest workspace", 230), ("Finding", 400) })
            dashboard.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = title, MinimumWidth = width });
        dashboard.SelectionChanged += (_, _) => ShowScanDetails();
        dashboard.CellDoubleClick += async (_, _) => await ExploreSelected();
        dashboard.CellFormatting += (_, e) =>
        {
            if (e.ColumnIndex != 1 || e.RowIndex < 0) return;
            bool connected = string.Equals(e.Value?.ToString(), "Connected", StringComparison.Ordinal);
            e.CellStyle.ForeColor = connected ? Color.FromArgb(20, 125, 87) : AppTheme.Muted;
            e.CellStyle.SelectionForeColor = e.CellStyle.ForeColor;
            e.CellStyle.Font = AppTheme.StatusFont;
        };
        AddConnectionMenu(dashboard);
    }

    private void BuildExplorer()
    {
        var tab = new TabPage("Folder explorer"); tabs.TabPages.Add(tab);
        var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 58, Padding = new Padding(8, 3, 0, 0), WrapContents = false, AutoScroll = true };
        top.Controls.Add(ActionButton("Review checked folders for deletion", async (_, _) => await ReviewDeletion()));
        top.Controls.Add(ActionButton("Clear checks", (_, _) => ClearFolderChecks()));
        top.Controls.Add(ActionButton("Pause agent", async (_, _) => await PauseSelected()));
        top.Controls.Add(ActionButton("Refresh tree", async (_, _) => { if (currentAgent is not null) await LoadRoot(currentAgent); }));
        var split = new SplitContainer { Dock = DockStyle.Fill, SplitterDistance = 650 };
        split.Panel1.Controls.Add(tree);
        split.Panel2.Controls.Add(folderDetails);
        tab.Controls.Add(split); tab.Controls.Add(location); tab.Controls.Add(top);
        location.Dock = DockStyle.Top;
        tree.BeforeExpand += async (_, e) => { if (e.Node is not null) await LoadChildren(e.Node); };
        tree.AfterSelect += (_, _) => ShowFolderDetails();
        tree.BeforeCheck += (_, e) =>
        {
            if (e.Node?.Tag is not FolderTag tag || tag.IsRoot || tag.Item["type"]?.GetValue<string>() != "directory")
            {
                e.Cancel = true;
                return;
            }
            if (!e.Node.Checked && (CheckedAncestor(e.Node) || CheckedDescendant(e.Node)))
            {
                e.Cancel = true;
                MessageBox.Show(this, "A checked parent or child folder already covers this path. Uncheck it before selecting this folder.",
                    "Overlapping folders", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        };
        tree.AfterCheck += (_, _) => UpdateCheckedCount();
    }

    private void BuildSettings()
    {
        var tab = new TabPage("Settings"); tabs.TabPages.Add(tab);
        var panel = new TableLayoutPanel { Dock = DockStyle.Top, ColumnCount = 2, RowCount = 3, AutoSize = true, Padding = new Padding(12) };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 180));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        AddSetting(panel, 0, "Jenkins HTTPS URL", jenkinsUrl);
        AddSetting(panel, 1, "Jenkins username", jenkinsUser);
        AddSetting(panel, 2, "Jenkins API token", jenkinsToken);
        foreach (var (header, property, width) in new[] {
            ("Jenkins node", "Name", 200), ("SSH host/IP", "Host", 120), ("SSH user", "Username", 90),
            ("Port", "Port", 55), ("Workspace root", "WorkspaceRoot", 250) })
            agentGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = header, DataPropertyName = property, MinimumWidth = width });
        agentGrid.DataSource = agents;
        agentGrid.CellDoubleClick += (_, _) => EditSelectedAgent();
        AddConnectionMenu(agentGrid);
        var bottom = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 106, Padding = new Padding(8, 5, 0, 0), AutoScroll = true };
        bottom.Controls.Add(ActionButton("Add agent", (_, _) => AddAgent()));
        bottom.Controls.Add(ActionButton("Edit selected", (_, _) => EditSelectedAgent()));
        bottom.Controls.Add(ActionButton("Remove selected", (_, _) => RemoveSelectedAgent()));
        bottom.Controls.Add(ActionButton("Add supplied agents", (_, _) => AddSuppliedAgents()));
        bottom.Controls.Add(ActionButton("Save settings", (_, _) => SaveSettings()));
        bottom.Controls.Add(ActionButton("Test selected SSH", async (_, _) => await TestSelectedSsh()));
        bottom.Controls.Add(ActionButton("Test Jenkins API", async (_, _) => await TestJenkins()));
        var help = new Label { Dock = DockStyle.Bottom, Height = 72, Padding = new Padding(12), Text =
            "Double-click an agent to edit its SSH login, workspace root, and protected paths. " +
            "Supplied agents have blank passwords. The first SSH connection asks you to trust the agent's identity. " +
            "Passwords and the API token are encrypted for this Windows user. Separate protected paths with semicolons. " +
            "The executable itself is the only file you distribute." };
        tab.Controls.Add(agentGrid); tab.Controls.Add(help); tab.Controls.Add(bottom); tab.Controls.Add(panel);
    }

    private static void AddSetting(TableLayoutPanel panel, int row, string title, TextBox field)
    {
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        panel.Controls.Add(new Label { Text = title, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(3, 9, 3, 3) }, 0, row);
        field.Dock = DockStyle.Top;
        panel.Controls.Add(field, 1, row);
    }

    private void FillSettings()
    {
        jenkinsUrl.Text = settings.JenkinsUrl; jenkinsUser.Text = settings.JenkinsUser; jenkinsToken.Text = settings.JenkinsToken;
    }

    private bool SaveSettings()
    {
        try
        {
            settings.JenkinsUrl = jenkinsUrl.Text.Trim(); settings.JenkinsUser = jenkinsUser.Text.Trim(); settings.JenkinsToken = jenkinsToken.Text.Trim();
            settings.Agents = agents.ToList();
            if (settings.JenkinsUrl.Length > 0 &&
                (!Uri.TryCreate(settings.JenkinsUrl, UriKind.Absolute, out var uri) || uri.Scheme != "https"))
                throw new InvalidOperationException("Use an HTTPS Jenkins URL");
            if (settings.Agents.Select(a => a.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count() != settings.Agents.Count)
                throw new InvalidOperationException("Jenkins node names must be unique");
            foreach (var agent in settings.Agents)
            {
                if (string.IsNullOrWhiteSpace(agent.Name) || string.IsNullOrWhiteSpace(agent.Host) ||
                    string.IsNullOrWhiteSpace(agent.Username) || agent.Port is < 1 or > 65535)
                    throw new InvalidOperationException($"Check name, host, SSH user, and port for {agent.Name}");
                if (agent.WorkspaceRoot.Length > 0 && (!agent.WorkspaceRoot.StartsWith('/') || agent.WorkspaceRoot.TrimEnd('/').Length == 0))
                    throw new InvalidOperationException($"Workspace root for {agent.Name} must be a specific absolute Linux path");
                if (agent.ProtectedPathList.Any(path => !path.StartsWith('/')))
                    throw new InvalidOperationException($"Protected paths for {agent.Name} must be absolute");
            }
            LocalStore.Save(settings); status.Text = "Settings saved for this Windows user";
            Log($"Settings saved for {settings.Agents.Count} agents.");
            PopulateDashboardPlaceholders();
            return true;
        }
        catch (Exception exc) { MessageBox.Show(exc.Message, "Settings", MessageBoxButtons.OK, MessageBoxIcon.Warning); return false; }
    }

    private void PopulateDashboardPlaceholders()
    {
        dashboard.Rows.Clear();
        foreach (var agent in agents)
        {
            int row = dashboard.Rows.Add(agent.Name, probe.IsConnected(agent) ? "Connected" : "Disconnected", "Not scanned", "—", "—", "—", "Set workspace root and SSH password, then scan");
            dashboard.Rows[row].Tag = agent;
        }
        UpdateConnectionDisplay();
    }

    private void AddAgent()
    {
        using var editor = new AgentEditorForm(new AgentProfile());
        if (editor.ShowDialog(this) != DialogResult.OK) return;
        if (agents.Any(agent => agent.Name.Equals(editor.Result.Name, StringComparison.OrdinalIgnoreCase)))
        { MessageBox.Show("An agent with that Jenkins node name already exists."); return; }
        agents.Add(editor.Result);
        PopulateDashboardPlaceholders();
        status.Text = $"Added {editor.Result.Name}; save settings when ready";
        Log($"Agent added: {editor.Result.Name} ({editor.Result.Host}).");
    }

    private async void EditSelectedAgent()
    {
        if (agentGrid.CurrentRow?.DataBoundItem is not AgentProfile existing)
        { MessageBox.Show("Select an agent to edit."); return; }
        using var editor = new AgentEditorForm(existing);
        if (editor.ShowDialog(this) != DialogResult.OK) return;
        if (agents.Any(agent => !ReferenceEquals(agent, existing) && agent.Name.Equals(editor.Result.Name, StringComparison.OrdinalIgnoreCase)))
        { MessageBox.Show("An agent with that Jenkins node name already exists."); return; }
        await probe.DisconnectAsync(existing);
        int index = agents.IndexOf(existing);
        agents[index] = editor.Result;
        if (ReferenceEquals(currentAgent, existing)) currentAgent = editor.Result;
        PopulateDashboardPlaceholders();
        status.Text = $"Updated {editor.Result.Name}; save settings when ready";
        Log($"Agent updated: {editor.Result.Name} ({editor.Result.Host}).");
    }

    private async void RemoveSelectedAgent()
    {
        if (agentGrid.CurrentRow?.DataBoundItem is not AgentProfile existing)
        { MessageBox.Show("Select an agent to remove."); return; }
        if (MessageBox.Show($"Remove {existing.Name} from this tool? No agent files will be changed.",
            "Remove agent", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        await probe.DisconnectAsync(existing);
        agents.Remove(existing);
        if (ReferenceEquals(currentAgent, existing)) currentAgent = null;
        PopulateDashboardPlaceholders();
        status.Text = $"Removed {existing.Name}; save settings when ready";
        Log($"Agent removed from tool: {existing.Name}.");
    }

    private void AddSuppliedAgents()
    {
        int added = SuggestedAgents.AddMissing(agents);
        PopulateDashboardPlaceholders();
        status.Text = added == 0 ? "All supplied agents are already present" : $"Added {added} supplied agents with blank passwords; save settings when ready";
        Log(added == 0 ? "Supplied agents already present." : $"Added {added} supplied agent profiles with blank passwords.");
    }

    private async Task TestSelectedSsh()
    {
        if (agentGrid.CurrentRow?.DataBoundItem is not AgentProfile agent)
        { MessageBox.Show("Select an agent in Settings first."); return; }
        if (!SaveSettings()) return;
        try
        {
            status.Text = $"Testing SSH to {agent.Host}:{agent.Port}…";
            Log($"SSH test started: {agent.Name} at {agent.Host}:{agent.Port}.");
            string result = await probe.TestConnectionAsync(settings, agent, ConfirmNewHostKey);
            status.Text = result;
            Log($"SSH test succeeded: {result}");
            MessageBox.Show(this, result, "SSH connection", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception exc)
        {
            status.Text = "SSH connection failed";
            Log($"SSH test failed for {agent.Name}: {exc.Message}");
            MessageBox.Show(this, exc.Message, "SSH connection", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private async Task TestJenkins()
    {
        if (!SaveSettings()) return;
        try
        {
            status.Text = "Testing Jenkins API…";
            Log("Jenkins API test started.");
            string result = await new JenkinsApi(settings).TestAsync();
            status.Text = result;
            Log($"Jenkins API test succeeded: {result}");
            MessageBox.Show(this, result, "Jenkins API", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception exc)
        {
            status.Text = "Jenkins API test failed";
            Log($"Jenkins API test failed: {exc.Message}");
            MessageBox.Show(this, exc.Message, "Jenkins API", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private AgentProfile? SelectedAgent() => tabs.SelectedIndex == 1
        ? currentAgent : dashboard.CurrentRow?.Tag as AgentProfile ?? currentAgent;

    private Task<JsonObject> RunProbeAsync(AgentProfile agent, string operation,
        string? path = null, JsonObject? expected = null) =>
        probe.RunAsync(settings, agent, operation, path, expected, ConfirmNewHostKey);

    private bool ConfirmNewHostKey(AgentProfile agent, string fingerprint)
    {
        if (InvokeRequired)
            return (bool)Invoke(new Func<bool>(() => ConfirmNewHostKey(agent, fingerprint)));
        var choice = MessageBox.Show(this,
            $"First SSH connection to {agent.Name} ({agent.Host}).\n\n" +
            $"The server presented this identity:\n{fingerprint}\n\n" +
            "Confirm that this is the expected agent before trusting it. Trust this identity for future connections?",
            "Trust SSH agent", MessageBoxButtons.YesNo, MessageBoxIcon.Question,
            MessageBoxDefaultButton.Button2);
        if (choice != DialogResult.Yes)
        {
            Log($"SSH identity rejected for {agent.Name} ({agent.Host}).");
            return false;
        }
        agent.HostKeySha256 = fingerprint;
        settings.Agents = agents.ToList();
        LocalStore.Save(settings);
        LocalStore.Audit("trust_ssh_host", agent.Name, agent.Host, fingerprint);
        Log($"SSH identity trusted for {agent.Name} ({agent.Host}).");
        return true;
    }

    private async Task ScanAll()
    {
        if (busy || !SaveSettings()) return;
        busy = true; status.Text = "Scanning Jenkins and Linux agents…"; dashboard.Rows.Clear();
        Log($"Scan started for {settings.Agents.Count} agents.");
        var api = new JenkinsApi(settings);
        var results = await Task.WhenAll(settings.Agents.Select(async agent =>
        {
            JsonObject? scan = null; JenkinsState? jenkins = null; string errors = "";
            Log($"{agent.Name}: checking Jenkins state.");
            try
            {
                jenkins = await api.StatusAsync(agent);
                Log($"{agent.Name}: Jenkins {(jenkins.TemporarilyOffline ? "maintenance" : jenkins.Offline ? "offline" : "online")}, {jenkins.ActiveBuilds.Count} active builds.");
            }
            catch (Exception exc) { errors += "Jenkins: " + exc.Message + " "; Log($"{agent.Name}: Jenkins check failed: {exc.Message}"); }
            Log($"{agent.Name}: collecting disk, workspace, and process data over SSH.");
            try
            {
                scan = await RunProbeAsync(agent, "scan");
                Log($"{agent.Name}: SSH scan completed; {FormatBytes(scan["disk"]?["free"]?.GetValue<long>() ?? 0)} disk free.");
            }
            catch (Exception exc) { errors += "SSH: " + exc.Message; Log($"{agent.Name}: SSH scan failed: {exc.Message}"); }
            return (agent, scan, jenkins, errors);
        }));
        foreach (var (agent, scan, jenkins, errors) in results)
        {
            string jenkinsText = jenkins is null ? "Unavailable" : $"{(jenkins.TemporarilyOffline ? "Maintenance" : jenkins.Offline ? "Offline" : "Online")}; {jenkins.ActiveBuilds.Count} active";
            string disk = scan is null ? "—" : FormatBytes(scan["disk"]?["free"]?.GetValue<long>() ?? 0);
            string inodes = scan?["inodes"]?["free"]?.ToString() ?? "—";
            var children = scan?["listing"]?["children"]?.AsArray();
            string largest = children is { Count: > 0 } ? $"{children[0]?["name"]} ({FormatBytes(children[0]?["size"]?.GetValue<long>() ?? 0)})" : "—";
            string finding = errors.Length > 0 ? errors : Finding(scan!);
            int row = dashboard.Rows.Add(agent.Name, probe.IsConnected(agent) ? "Connected" : "Disconnected", jenkinsText, disk, inodes, largest, finding);
            dashboard.Rows[row].Tag = agent;
            dashboard.Rows[row].Cells[0].Tag = scan;
        }
        UpdateConnectionDisplay();
        LocalStore.Audit("scan", "all", "", $"{results.Length} agents");
        status.Text = $"Scanned {results.Length} agents"; busy = false;
        Log($"Scan finished: {results.Count(result => result.scan is not null)} of {results.Length} agents returned filesystem data.");
    }

    private static string Finding(JsonObject scan)
    {
        long total = scan["disk"]?["total"]?.GetValue<long>() ?? 0;
        long free = scan["disk"]?["free"]?.GetValue<long>() ?? 0;
        long inodeTotal = scan["inodes"]?["total"]?.GetValue<long>() ?? 0;
        long inodeFree = scan["inodes"]?["free"]?.GetValue<long>() ?? 0;
        var children = scan["listing"]?["children"]?.AsArray();
        bool incomplete = children?.Any(x => x?["errors"]?.AsArray().Count > 0) ?? false;
        bool writer = scan["processes"]?.AsArray().Any(x => (x?["write_bytes_per_second"]?.GetValue<double>() ?? 0) > 1_000_000) ?? false;
        if (incomplete) return "Some folders could not be measured; inspect permissions or mounts";
        if (inodeTotal > 0 && inodeFree * 10 < inodeTotal) return "Low free inodes; inspect file counts";
        if (total > 0 && free * 10 < total) return writer ? "Low disk space and active writer; inspect process before cleanup" : "Low disk space; explore largest folders";
        if (writer) return "Active writer observed; match process to build/log path";
        return "No obvious pressure in this snapshot";
    }

    private void ShowScanDetails()
    {
        var scan = dashboard.CurrentRow?.Cells[0].Tag as JsonObject;
        if (scan is null) { scanDetails.Text = ""; return; }
        var lines = new List<string>();
        long total = scan["disk"]?["total"]?.GetValue<long>() ?? 0;
        long free = scan["disk"]?["free"]?.GetValue<long>() ?? 0;
        lines.Add($"Disk: {FormatBytes(free)} free of {FormatBytes(total)}. Probe UID: {scan["probe_uid"]}.");
        lines.Add("Largest workspace entries:");
        foreach (var item in scan["listing"]?["children"]?.AsArray().Take(10) ?? Enumerable.Empty<JsonNode?>())
            lines.Add($"  {item?["path"]} — {FormatBytes(item?["size"]?.GetValue<long>() ?? 0)}{(item?["errors"]?.AsArray().Count > 0 ? " (size incomplete)" : "")}");
        lines.Add("Processes (short sample):");
        foreach (var item in scan["processes"]?.AsArray().Take(8) ?? Enumerable.Empty<JsonNode?>())
            lines.Add($"  PID {item?["pid"]}: CPU {item?["cpu_percent"]}% / write {FormatBytes((long)(item?["write_bytes_per_second"]?.GetValue<double>() ?? 0))}/s — {item?["command"]}");
        scanDetails.Text = string.Join(Environment.NewLine, lines);
    }

    private static string FormatBytes(long value)
    {
        string[] units = ["B", "KiB", "MiB", "GiB", "TiB"];
        double amount = value; int i = 0;
        while (amount >= 1024 && i < units.Length - 1) { amount /= 1024; i++; }
        return $"{amount:0.0} {units[i]}";
    }

    private async Task ExploreSelected()
    {
        AgentProfile? agent = SelectedAgent();
        if (agent is null) { MessageBox.Show("Select an agent first."); return; }
        currentAgent = agent; tabs.SelectedIndex = 1; await LoadRoot(agent);
    }

    private async Task LoadRoot(AgentProfile agent)
    {
        try
        {
            status.Text = "Loading workspace tree…"; tree.Nodes.Clear();
            Log($"{agent.Name}: loading workspace root {agent.WorkspaceRoot}.");
            JsonObject data = await RunProbeAsync(agent, "browse", agent.WorkspaceRoot);
            var root = new TreeNode($"{agent.Name}: {agent.WorkspaceRoot}") { Tag = new FolderTag(agent, data["listing"]!.AsObject(), true) };
            tree.Nodes.Add(root); AddChildren(root, data["listing"]!["children"]!.AsArray()); root.Expand(); tree.SelectedNode = root;
            location.Text = $"{agent.Name} — {agent.WorkspaceRoot}"; status.Text = "Folder sizes loaded";
            Log($"{agent.Name}: loaded {data["listing"]?["children"]?.AsArray().Count ?? 0} top-level workspace entries.");
        }
        catch (Exception exc) { status.Text = "Folder load failed"; Log($"{agent.Name}: workspace load failed: {exc.Message}"); MessageBox.Show(exc.Message, "Explorer", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
    }

    private sealed record FolderTag(AgentProfile Agent, JsonObject Item, bool IsRoot = false);

    private static IEnumerable<TreeNode> Descendants(TreeNode node)
    {
        foreach (TreeNode child in node.Nodes)
        {
            yield return child;
            foreach (var deeper in Descendants(child)) yield return deeper;
        }
    }

    private static bool CheckedAncestor(TreeNode node)
    {
        for (TreeNode? parent = node.Parent; parent is not null; parent = parent.Parent)
            if (parent.Checked) return true;
        return false;
    }

    private static bool CheckedDescendant(TreeNode node) => Descendants(node).Any(child => child.Checked);

    private List<FolderTag> CheckedFolders() => tree.Nodes.Cast<TreeNode>()
        .SelectMany(root => Descendants(root))
        .Where(node => node.Checked && node.Tag is FolderTag)
        .Select(node => (FolderTag)node.Tag!)
        .ToList();

    private void ClearFolderChecks()
    {
        foreach (TreeNode root in tree.Nodes)
            foreach (var node in Descendants(root)) node.Checked = false;
        UpdateCheckedCount();
    }

    private void UpdateCheckedCount()
    {
        int count = CheckedFolders().Count;
        status.Text = count == 0 ? "No folders checked for deletion" :
            $"{count} folder{(count == 1 ? "" : "s")} checked for deletion review";
    }

    private static void AddChildren(TreeNode parent, JsonArray children)
    {
        parent.Nodes.Clear();
        foreach (var child in children)
        {
            if (child is not JsonObject item) continue;
            string name = item["name"]?.GetValue<string>() ?? "?";
            string type = item["type"]?.GetValue<string>() ?? "?";
            var node = new TreeNode($"{name}   [{FormatBytes(item["size"]?.GetValue<long>() ?? 0)}]{(type == "symlink" ? "  ↗ symlink" : "")}")
                { Tag = new FolderTag(((FolderTag)parent.Tag!).Agent, item) };
            if (type == "directory") node.Nodes.Add(new TreeNode("Loading…"));
            parent.Nodes.Add(node);
        }
    }

    private async Task LoadChildren(TreeNode node)
    {
        if (node.Tag is not FolderTag tag || tag.Item["type"]?.GetValue<string>() != "directory") return;
        if (node.Nodes.Count != 1 || node.Nodes[0].Tag is not null) return;
        try
        {
            string path = tag.Item["path"]!.GetValue<string>();
            Log($"{tag.Agent.Name}: measuring subfolders of {path}.");
            JsonObject data = await RunProbeAsync(tag.Agent, "browse", path);
            AddChildren(node, data["listing"]!["children"]!.AsArray());
            Log($"{tag.Agent.Name}: loaded {node.Nodes.Count} entries under {path}.");
        }
        catch (Exception exc) { node.Nodes.Clear(); Log($"{tag.Agent.Name}: folder measurement failed: {exc.Message}"); MessageBox.Show(exc.Message, "Folder", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
    }

    private void ShowFolderDetails()
    {
        if (tree.SelectedNode?.Tag is not FolderTag tag) { folderDetails.Text = ""; return; }
        var item = tag.Item;
        string path = item["path"]?.GetValue<string>() ?? tag.Agent.WorkspaceRoot;
        var errors = item["errors"]?.AsArray().Select(x => x?.ToString()) ?? [];
        folderDetails.Text = $"Agent: {tag.Agent.Name}\r\nPath: {path}\r\nType: {item["type"] ?? "directory"}\r\n" +
            $"Recursive size: {FormatBytes(item["size"]?.GetValue<long>() ?? 0)}\r\nOwner UID: {item["owner_uid"]}\r\nMode: {item["mode"]}\r\n" +
            (errors.Any() ? "\r\nMeasurement errors:\r\n" + string.Join("\r\n", errors) : "");
        location.Text = $"{tag.Agent.Name} — {path}";
    }

    private async Task PauseSelected()
    {
        AgentProfile? agent = SelectedAgent();
        if (agent is null) { MessageBox.Show("Select an agent first."); return; }
        if (MessageBox.Show($"Pause new Jenkins builds on {agent.Name}? Existing builds will continue.", "Approve maintenance", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        Log($"{agent.Name}: requesting Jenkins maintenance mode.");
        try { await new JenkinsApi(settings).PauseAsync(agent); LocalStore.Audit("pause", agent.Name, "", "success"); status.Text = $"{agent.Name} in maintenance mode"; Log($"{agent.Name}: Jenkins maintenance mode confirmed."); }
        catch (Exception exc) { Log($"{agent.Name}: Jenkins pause failed: {exc.Message}"); MessageBox.Show(exc.Message, "Jenkins pause", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
    }

    private async Task ResumeSelected()
    {
        AgentProfile? agent = SelectedAgent();
        if (agent is null) { MessageBox.Show("Select an agent first."); return; }
        if (MessageBox.Show($"Resume Jenkins scheduling on {agent.Name}?", "Approve resume", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        Log($"{agent.Name}: requesting Jenkins scheduling resume.");
        try { await new JenkinsApi(settings).ResumeAsync(agent); LocalStore.Audit("resume", agent.Name, "", "success"); status.Text = $"{agent.Name} resumed"; Log($"{agent.Name}: Jenkins scheduling resumed."); }
        catch (Exception exc) { Log($"{agent.Name}: Jenkins resume failed: {exc.Message}"); MessageBox.Show(exc.Message, "Jenkins resume", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
    }

    private async Task ReviewDeletion()
    {
        var selected = CheckedFolders();
        if (selected.Count == 0)
        { MessageBox.Show("Check one or more folders below the workspace root first."); return; }
        AgentProfile agent = selected[0].Agent;
        var paths = selected.Select(folder => folder.Item["path"]!.GetValue<string>()).ToList();
        if (selected.Any(folder => folder.IsRoot || folder.Item["type"]?.GetValue<string>() != "directory" ||
            !ReferenceEquals(folder.Agent, agent)) || paths.Distinct(StringComparer.Ordinal).Count() != paths.Count ||
            paths.Any(path => paths.Any(other => other != path && path.StartsWith(other.TrimEnd('/') + "/", StringComparison.Ordinal))))
        { MessageBox.Show("The checked folders overlap or include an invalid item. Clear checks and select separate folders."); return; }
        int completed = 0;
        try
        {
            status.Text = $"Measuring {selected.Count} checked folders and checking Jenkins…";
            Log($"{agent.Name}: deletion review started for {selected.Count} checked folders.");
            var api = new JenkinsApi(settings);
            JenkinsState state = await api.StatusAsync(agent);
            if (!state.TemporarilyOffline || state.ActiveBuilds.Count > 0)
                throw new InvalidOperationException($"Put {agent.Name} in maintenance mode and wait for its {state.ActiveBuilds.Count} active builds to finish");
            var reviewed = new List<(string Path, long Size, JsonObject Snapshot)>();
            foreach (string path in paths)
            {
                JsonObject snapshot = (await RunProbeAsync(agent, "inspect", path))["item"]!.AsObject();
                if (snapshot["type"]?.GetValue<string>() != "directory" || snapshot["errors"]?.AsArray().Count > 0)
                    throw new InvalidOperationException($"Cannot safely measure {path}; review its type and access errors before deletion");
                long size = snapshot["size"]?.GetValue<long>() ?? 0;
                reviewed.Add((path, size, snapshot));
                Log($"{agent.Name}: measured {path} ({FormatBytes(size)}).");
            }
            using var dialog = new ConfirmDeleteForm(agent.Name, reviewed.Select(item => (item.Path, item.Size)).ToList());
            if (dialog.ShowDialog(this) != DialogResult.OK)
            { status.Text = "Deletion cancelled"; Log($"{agent.Name}: deletion of checked folders cancelled."); return; }
            foreach (var item in reviewed)
                LocalStore.Audit("approved_delete", agent.Name, item.Path, "operator confirmed checked-folder review");
            Log($"{agent.Name}: operator approved {reviewed.Count} exact paths; rechecking Jenkins before each deletion.");
            foreach (var item in reviewed)
            {
                state = await api.StatusAsync(agent);
                if (!state.TemporarilyOffline || state.ActiveBuilds.Count > 0)
                    throw new InvalidOperationException($"Jenkins state changed before deleting {item.Path}; remaining folders were not deleted");
                JsonObject result = await RunProbeAsync(agent, "delete", item.Path, item.Snapshot);
                completed++;
                LocalStore.Audit("deleted", agent.Name, item.Path, result.ToJsonString());
                Log($"{agent.Name}: deleted {item.Path} ({completed}/{reviewed.Count}).");
            }
            status.Text = $"Deleted {completed} folders. Agent remains in maintenance mode.";
            MessageBox.Show(this, $"Deleted {completed} folders. Verify free space, then resume the agent when ready.",
                "Completed", MessageBoxButtons.OK, MessageBoxIcon.Information);
            await LoadRoot(agent);
        }
        catch (Exception exc)
        {
            LocalStore.Audit("delete_failed", agent.Name, string.Join(";", paths), exc.Message);
            status.Text = $"Deletion stopped; {completed} of {selected.Count} folders completed";
            Log($"{agent.Name}: deletion stopped after {completed} of {selected.Count} folders: {exc.Message}");
            MessageBox.Show(this, $"Deleted {completed} of {selected.Count} folders.\n\n{exc.Message}\n\nRefresh the tree before another review.",
                "Deletion stopped", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            if (completed > 0) await LoadRoot(agent);
        }
    }
}

public sealed class ConfirmDeleteForm : Form
{
    public ConfirmDeleteForm(string agent, IReadOnlyList<(string Path, long Size)> folders)
    {
        Text = "Approve permanent deletion"; Width = 860; Height = 550; MinimumSize = new Size(700, 440);
        StartPosition = FormStartPosition.CenterParent;
        string approval = folders.Count == 1 ? folders[0].Path : $"DELETE {folders.Count} FOLDERS";
        var heading = new Label { Dock = DockStyle.Top, Height = 80, Padding = new Padding(14), Text =
            $"Agent: {agent}\r\nFolders: {folders.Count}     Total measured size: {FormatTotal(folders)}\r\nThese exact paths will be permanently deleted. Type {(folders.Count == 1 ? "the complete path" : approval)} below to approve." };
        var list = new DataGridView { Dock = DockStyle.Fill, ReadOnly = true, AllowUserToAddRows = false,
            AllowUserToDeleteRows = false, RowHeadersVisible = false, SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill };
        list.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Exact folder path", FillWeight = 85 });
        list.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Measured size", FillWeight = 15, MinimumWidth = 120 });
        foreach (var folder in folders) list.Rows.Add(folder.Path, FormatSize(folder.Size));
        var input = new TextBox { Dock = DockStyle.Bottom, Margin = new Padding(14), PlaceholderText = approval };
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, FlowDirection = FlowDirection.RightToLeft, Height = 54 };
        var approve = new Button { Text = $"Delete {folders.Count} folder{(folders.Count == 1 ? "" : "s")}", AutoSize = true, DialogResult = DialogResult.None };
        approve.Click += (_, _) =>
        {
            if (input.Text == approval) { DialogResult = DialogResult.OK; Close(); }
            else MessageBox.Show(this, $"Type {approval} exactly to approve these paths.");
        };
        buttons.Controls.Add(approve);
        buttons.Controls.Add(new Button { Text = "Cancel", AutoSize = true, DialogResult = DialogResult.Cancel });
        Controls.Add(list); Controls.Add(input); Controls.Add(buttons); Controls.Add(heading);
        AcceptButton = approve;
        AppTheme.Apply(this);
        Controls.Add(AppTheme.CreateBanner("Review permanent deletion", "Check every path and measured size before approving"));
    }

    private static string FormatSize(long bytes)
    {
        string[] units = ["B", "KiB", "MiB", "GiB", "TiB"];
        double value = bytes; int unit = 0;
        while (value >= 1024 && unit < units.Length - 1) { value /= 1024; unit++; }
        return $"{value:0.0} {units[unit]}";
    }

    private static string FormatTotal(IReadOnlyList<(string Path, long Size)> folders) =>
        FormatSize(folders.Sum(folder => folder.Size));
}
