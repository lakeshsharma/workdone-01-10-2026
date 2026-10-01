using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Renci.SshNet;
using Renci.SshNet.Common;

namespace AgentRecovery;

public sealed record JenkinsState(bool Offline, bool TemporarilyOffline, List<string> ActiveBuilds);

public sealed class JenkinsApi(AppSettings settings)
{
    private readonly HttpClient http = CreateClient(settings);

    private static HttpClient CreateClient(AppSettings settings)
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        string basic = Convert.ToBase64String(Encoding.UTF8.GetBytes(settings.JenkinsUser + ":" + settings.JenkinsToken));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", basic);
        return client;
    }

    private string BaseUrl => settings.JenkinsUrl.TrimEnd('/');
    private static string NodeSegment(string name) => Uri.EscapeDataString(name);

    public async Task<string> TestAsync()
    {
        if (string.IsNullOrWhiteSpace(settings.JenkinsUrl) ||
            string.IsNullOrWhiteSpace(settings.JenkinsUser) ||
            string.IsNullOrWhiteSpace(settings.JenkinsToken))
            throw new InvalidOperationException("Enter the Jenkins HTTPS URL, username, and that user's Jenkins API token.");
        using var response = await http.GetAsync($"{BaseUrl}/whoAmI/api/json?tree=name,authenticated");
        response.EnsureSuccessStatusCode();
        var data = JsonNode.Parse(await response.Content.ReadAsStringAsync())?.AsObject()
            ?? throw new InvalidOperationException("Jenkins returned an invalid authentication response");
        if (data["authenticated"]?.GetValue<bool>() != true)
            throw new InvalidOperationException("Jenkins did not authenticate the supplied username and API token");
        return $"Jenkins API authenticated as {data["name"]?.GetValue<string>() ?? settings.JenkinsUser}.";
    }

    public async Task<JenkinsState> StatusAsync(AgentProfile agent)
    {
        const string tree = "displayName,offline,temporarilyOffline,executors[currentExecutable[fullDisplayName]],oneOffExecutors[currentExecutable[fullDisplayName]]";
        string url = $"{BaseUrl}/computer/{NodeSegment(agent.Name)}/api/json?tree={Uri.EscapeDataString(tree)}";
        using var response = await http.GetAsync(url);
        response.EnsureSuccessStatusCode();
        var node = JsonNode.Parse(await response.Content.ReadAsStringAsync())?.AsObject()
            ?? throw new InvalidOperationException("Jenkins returned no node data");
        if (node["temporarilyOffline"] is null) throw new InvalidOperationException("Jenkins did not report maintenance state");
        var active = new List<string>();
        foreach (string key in new[] { "executors", "oneOffExecutors" })
            foreach (JsonNode? executor in node[key]?.AsArray() ?? new JsonArray())
            {
                string? title = executor?["currentExecutable"]?["fullDisplayName"]?.GetValue<string>();
                if (title is not null) active.Add(title);
            }
        return new(node["offline"]?.GetValue<bool>() ?? false,
            node["temporarilyOffline"]!.GetValue<bool>(), active);
    }

    public async Task PauseAsync(AgentProfile agent)
    {
        var before = await StatusAsync(agent);
        if (before.TemporarilyOffline) return;
        string url = $"{BaseUrl}/computer/{NodeSegment(agent.Name)}/toggleOffline?offlineMessage={Uri.EscapeDataString("Agent Recovery maintenance")}";
        using var response = await http.PostAsync(url, new StringContent(""));
        response.EnsureSuccessStatusCode();
        if (!(await StatusAsync(agent)).TemporarilyOffline)
            throw new InvalidOperationException("Jenkins did not confirm maintenance mode");
    }

    public async Task ResumeAsync(AgentProfile agent)
    {
        var before = await StatusAsync(agent);
        if (!before.TemporarilyOffline) return;
        string url = $"{BaseUrl}/computer/{NodeSegment(agent.Name)}/toggleOffline";
        using var response = await http.PostAsync(url, new StringContent(""));
        response.EnsureSuccessStatusCode();
    }
}

public sealed class LinuxProbe
{
    private static readonly string SourceBase64 = LoadSource();
    private sealed class AgentSession
    {
        public readonly SemaphoreSlim Gate = new(1, 1);
        public SshClient? Client;
    }
    private readonly ConcurrentDictionary<AgentProfile, AgentSession> sessions = new();
    public event Action<AgentProfile, bool>? ConnectionChanged;

    public bool IsConnected(AgentProfile agent) =>
        sessions.TryGetValue(agent, out var session) && session.Client?.IsConnected == true;

    private SshClient EnsureConnected(AppSettings settings, AgentProfile agent, AgentSession session,
        Func<AgentProfile, string, bool>? trustNewHost)
    {
        if (session.Client?.IsConnected == true) return session.Client;
        if (session.Client is not null) MarkDisconnected(agent, session);
        var client = Connect(settings, agent, trustNewHost);
        client.KeepAliveInterval = TimeSpan.FromSeconds(15);
        session.Client = client;
        ConnectionChanged?.Invoke(agent, true);
        return client;
    }

    private void MarkDisconnected(AgentProfile agent, AgentSession session)
    {
        if (session.Client is null) return;
        try { session.Client.Disconnect(); } catch { }
        session.Client.Dispose();
        session.Client = null;
        ConnectionChanged?.Invoke(agent, false);
    }

    public Task<string> ConnectNowAsync(AppSettings settings, AgentProfile agent,
        Func<AgentProfile, string, bool>? trustNewHost = null) => Task.Run(async () =>
    {
        var session = sessions.GetOrAdd(agent, _ => new AgentSession());
        await session.Gate.WaitAsync();
        try
        {
            EnsureConnected(settings, agent, session, trustNewHost);
            return $"SSH connected to {agent.Host}:{agent.Port} as {settings.CredentialsFor(agent).User}.";
        }
        finally { session.Gate.Release(); }
    });

    public async Task DisconnectAsync(AgentProfile agent)
    {
        if (!sessions.TryGetValue(agent, out var session)) return;
        await session.Gate.WaitAsync();
        try { MarkDisconnected(agent, session); }
        finally { session.Gate.Release(); }
    }

    public void DisconnectAll()
    {
        foreach (var (agent, session) in sessions)
        {
            session.Gate.Wait();
            try { MarkDisconnected(agent, session); }
            finally { session.Gate.Release(); }
        }
    }

    private static string LoadSource()
    {
        using Stream stream = typeof(LinuxProbe).Assembly.GetManifestResourceStream("AgentRecovery.remote_linux.py")
            ?? throw new InvalidOperationException("Embedded Linux probe is missing");
        using var memory = new MemoryStream();
        stream.CopyTo(memory);
        return Convert.ToBase64String(memory.ToArray());
    }

    public Task<JsonObject> RunAsync(AppSettings settings, AgentProfile agent, string operation,
        string? path = null, JsonObject? expected = null,
        Func<AgentProfile, string, bool>? trustNewHost = null) => Task.Run(async () =>
    {
        if (string.IsNullOrWhiteSpace(agent.WorkspaceRoot) || agent.WorkspaceRoot.TrimEnd('/') == "")
            throw new InvalidOperationException($"Set a specific workspace root for {agent.Name} in Settings");
        var request = new JsonObject
        {
            ["op"] = operation, ["root"] = agent.WorkspaceRoot,
            ["protected"] = new JsonArray(agent.ProtectedPathList.Select(x => (JsonNode?)JsonValue.Create(x)).ToArray())
        };
        if (path is not null) request["path"] = path;
        if (expected is not null) request["expected"] = expected.DeepClone();
        string payload = Convert.ToBase64String(Encoding.UTF8.GetBytes(request.ToJsonString()));
        string commandText = $"python3 -c 'import base64;exec(base64.b64decode(\"{SourceBase64}\"))' '{payload}'";
        var session = sessions.GetOrAdd(agent, _ => new AgentSession());
        await session.Gate.WaitAsync();
        try
        {
            var client = EnsureConnected(settings, agent, session, trustNewHost);
            try
            {
                using var command = client.CreateCommand(commandText);
                command.CommandTimeout = TimeSpan.FromMinutes(5);
                string output = command.Execute();
                if (command.ExitStatus != 0) throw new InvalidOperationException(command.Error.Trim());
                var result = JsonNode.Parse(output)?.AsObject() ?? throw new InvalidOperationException("Invalid response from agent");
                if (result["ok"]?.GetValue<bool>() != true)
                    throw new InvalidOperationException(result["error"]?.GetValue<string>() ?? "Agent probe failed");
                return result["data"]?.AsObject() ?? throw new InvalidOperationException("Agent response had no data");
            }
            catch
            {
                if (!client.IsConnected) MarkDisconnected(agent, session);
                throw;
            }
        }
        finally { session.Gate.Release(); }
    });

    public Task<string> TestConnectionAsync(AppSettings settings, AgentProfile agent,
        Func<AgentProfile, string, bool>? trustNewHost = null) => ConnectNowAsync(settings, agent, trustNewHost);

    private static SshClient Connect(AppSettings settings, AgentProfile agent,
        Func<AgentProfile, string, bool>? trustNewHost)
    {
        CredentialGroup credential = settings.CredentialsFor(agent);
        if (string.IsNullOrWhiteSpace(credential.User) || string.IsNullOrWhiteSpace(credential.Password))
            throw new InvalidOperationException($"SSH username or password is missing for {agent.Name}; edit this agent in Settings");
        var client = new SshClient(agent.Host, agent.Port, credential.User, credential.Password);
        client.ConnectionInfo.Timeout = TimeSpan.FromSeconds(15);
        string observed = "";
        client.HostKeyReceived += (_, args) =>
        {
            observed = "SHA256:" + Convert.ToBase64String(SHA256.HashData(args.HostKey)).TrimEnd('=');
            string saved = agent.HostKeySha256.Trim();
            if (saved.Length > 0)
            {
                args.CanTrust = CryptographicOperations.FixedTimeEquals(
                    Encoding.ASCII.GetBytes(observed), Encoding.ASCII.GetBytes(saved));
            }
            else
            {
                // This callback runs during SSH key exchange, before password authentication.
                // A new host is trusted only after the operator explicitly accepts its key.
                args.CanTrust = trustNewHost?.Invoke(agent, observed) == true;
                if (args.CanTrust) agent.HostKeySha256 = observed;
            }
        };
        try
        {
            client.Connect();
            return client;
        }
        catch (Exception exc)
        {
            client.Dispose();
            if (observed.Length > 0 &&
                (agent.HostKeySha256.Length == 0 || !CryptographicOperations.FixedTimeEquals(
                    Encoding.ASCII.GetBytes(observed), Encoding.ASCII.GetBytes(agent.HostKeySha256.Trim()))))
                throw new InvalidOperationException($"SSH identity for {agent.Name} was not trusted. Presented {observed}. If the agent was rebuilt, use Reset SSH trust, then verify the new identity.", exc);
            if (exc is SshAuthenticationException)
                throw new InvalidOperationException($"Reached {agent.Host}:{agent.Port}, but SSH rejected username/password for {credential.User}.", exc);
            if (exc is TimeoutException || exc is SshOperationTimeoutException ||
                exc.Message.Contains("within 15000 milliseconds", StringComparison.OrdinalIgnoreCase) ||
                exc.GetBaseException() is SocketException)
                throw new InvalidOperationException($"Could not reach SSH at {agent.Host}:{agent.Port} within 15 seconds. Check the IP/name mapping, VPN, firewall, port, and whether sshd is running. The password and workspace path were not checked.", exc);
            throw;
        }
    }
}
