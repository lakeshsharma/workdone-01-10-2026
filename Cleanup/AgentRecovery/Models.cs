using System.ComponentModel;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace AgentRecovery;

public sealed class AgentProfile
{
    public string Name { get; set; } = "";
    public string Host { get; set; } = "";
    public int Port { get; set; } = 22;
    public string WorkspaceRoot { get; set; } = "";
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    // Used only to migrate settings saved by the earlier two-group version.
    public string CredentialGroup { get; set; } = "A";
    public string HostKeySha256 { get; set; } = "";
    public string ProtectedPaths { get; set; } = "";
    public string[] ProtectedPathList => ProtectedPaths.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
}

public sealed class CredentialGroup
{
    public string User { get; set; } = "";
    public string Password { get; set; } = "";
}

public sealed class AppSettings
{
    public string JenkinsUrl { get; set; } = "";
    public string JenkinsUser { get; set; } = "";
    public string JenkinsToken { get; set; } = "";
    public CredentialGroup GroupA { get; set; } = new();
    public CredentialGroup GroupB { get; set; } = new();
    public List<AgentProfile> Agents { get; set; } = new();
    public int SuggestedAgentsVersion { get; set; }

    public CredentialGroup CredentialsFor(AgentProfile agent) =>
        !string.IsNullOrWhiteSpace(agent.Username)
            ? new CredentialGroup { User = agent.Username, Password = agent.Password }
            : agent.CredentialGroup.Equals("B", StringComparison.OrdinalIgnoreCase) ? GroupB : GroupA;

    public void MigrateLegacyCredentials()
    {
        foreach (var agent in Agents)
        {
            if (!string.IsNullOrWhiteSpace(agent.Username)) continue;
            var legacy = agent.CredentialGroup.Equals("B", StringComparison.OrdinalIgnoreCase) ? GroupB : GroupA;
            agent.Username = legacy.User;
            agent.Password = legacy.Password;
        }
        GroupA = new();
        GroupB = new();
    }
}

public static class SuggestedAgents
{
    private static readonly (string Name, string Host, string User)[] Defaults =
    [
        ("uslv-abudbld-05.dev.local", "10.152.73.132", "buddy"),
        ("uslv-abudbld-10.dev.local", "10.152.76.123", "build"),
        ("uslv-abudbld-09.dev.local", "10.152.77.129", "build"),
        ("uslv-abudbld-04.dev.local", "10.152.73.133", "buddy"),
        ("uslv-abudbld-196", "10.152.77.196", "build"),
        ("uslv-abudbld-08.dev.local", "10.152.72.43", "buddy")
    ];

    public static int AddMissing(ICollection<AgentProfile> agents)
    {
        int added = 0;
        foreach (var (name, host, user) in Defaults)
        {
            if (agents.Any(agent => agent.Name.Equals(name, StringComparison.OrdinalIgnoreCase))) continue;
            agents.Add(new AgentProfile { Name = name, Host = host, Username = user, Password = "" });
            added++;
        }
        return added;
    }

    public static string? OriginalNameForIp(string host) =>
        Defaults.FirstOrDefault(entry => entry.Host.Equals(host, StringComparison.OrdinalIgnoreCase)).Name;
}

public static class LocalStore
{
    public static readonly string DirectoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OneLinkAgentRecovery");
    private static string SettingsPath => Path.Combine(DirectoryPath, "settings.dat");
    private static string AuditPath => Path.Combine(DirectoryPath, "audit.jsonl");

    public static AppSettings Load()
    {
        if (!File.Exists(SettingsPath)) return new();
        byte[] encrypted = File.ReadAllBytes(SettingsPath);
        byte[] plain = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
        return JsonSerializer.Deserialize<AppSettings>(plain) ?? new();
    }

    public static void Save(AppSettings settings)
    {
        Directory.CreateDirectory(DirectoryPath);
        byte[] plain = JsonSerializer.SerializeToUtf8Bytes(settings);
        byte[] encrypted = ProtectedData.Protect(plain, null, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(SettingsPath, encrypted);
        CryptographicOperations.ZeroMemory(plain);
    }

    public static void Audit(string action, string agent, string path, string outcome)
    {
        Directory.CreateDirectory(DirectoryPath);
        var record = new { time = DateTimeOffset.UtcNow, user = Environment.UserName, action, agent, path, outcome };
        File.AppendAllText(AuditPath, JsonSerializer.Serialize(record) + Environment.NewLine, Encoding.UTF8);
    }
}
