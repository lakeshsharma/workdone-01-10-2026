# ----------------------------------------------------------------------------
#  Base directory: where the EXE (or script) lives.
#  Used ONLY for the external Logs folder and the optional external
#  Settings.json / NMenuMappings.json overrides.
# ----------------------------------------------------------------------------
if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $script:BaseDirectory = $PSScriptRoot
}
else {
    $script:BaseDirectory = [System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\')
}

# ============================================================================
#  EMBEDDED DEFAULT CONFIGURATION  (was Config\Settings.json)
# ============================================================================
$script:DefaultSettingsJson = @'
{
  "ApplicationName": "Foreman",
  "Ssh": {
    "DefaultPort": 22,
    "ConnectionTimeoutSeconds": 20,
    "CommandTimeoutSeconds": 120,
    "PromptTimeoutSeconds": 45,
    "AcceptNewHostKey": true,
    "TrustChangedHostKey": true,
    "TerminalName": "xterm",
    "TerminalWidth": 140,
    "TerminalHeight": 45,
    "BufferSize": 8192
  },
  "Remote": {
    "NMenuCommand": "nmenu",
    "UploadDirectory": "/tmp/onelink-admin-tool",
    "UseSudo": true,
    "ServiceUnitPattern": "onelink-*.service"
  },
  "Packages": {
    "AutoAnswer": "",
    "Types": {
      "rpm": {
        "Install": "sudo rpm -ivh --replacepkgs '{0}'",
        "Upgrade": "sudo rpm -Uvh '{0}'"
      },
      "deb": {
        "Install": "sudo DEBIAN_FRONTEND=noninteractive dpkg -i '{0}'; rc=$?; sudo DEBIAN_FRONTEND=noninteractive apt-get -y -f install >/dev/null 2>&1 || true; exit $rc",
        "Upgrade": "sudo DEBIAN_FRONTEND=noninteractive dpkg -i '{0}'; rc=$?; sudo DEBIAN_FRONTEND=noninteractive apt-get -y -f install >/dev/null 2>&1 || true; exit $rc"
      }
    }
  },
  "Logging": {
    "Directory": "Logs",
    "MinimumLevel": "Info"
  },
  "Services": [
    {
      "DisplayName": "AppServer",
      "SystemdName": "onelink-appserver"
    },
    {
      "DisplayName": "Concentrator",
      "SystemdName": "onelink-concentrator"
    },
    {
      "DisplayName": "Report Server",
      "SystemdName": "onelink-reportserver"
    },
    {
      "DisplayName": "MediaSign",
      "SystemdName": "onelink-mediasign"
    }
  ]
}
'@

# ============================================================================
#  EMBEDDED DEFAULT NMENU MAPPINGS  (was Config\NMenuMappings.json)
# ============================================================================
$script:DefaultMappingsJson = @'
{
  "Common": {
    "MainMenuPrompt": "(?i)(main menu|select.*option|enter.*choice|database|service)",
    "ContinuePrompt": "(?i)(press enter|hit enter|press any key|continue)",
    "GenericSuccess": "(?i)(success|successfully|completed|created|enabled|started|restarted)",
    "GenericFailure": "(?i)(failed|error|invalid|denied|not found)"
  },
  "Database": {
    "MainMenuKey": "a",
    "SubMenuPrompt": "(?i)(database menu|mysql|select.*option|enter.*choice)",
    "CreateUser": {
      "Key": "i",
      "UsernamePrompt": "(?i)(user.?name|mysql user)",
      "PasswordPrompt": "(?i)password",
      "IpPrompt": "(?i)(ip|host)",
      "SuccessPrompt": "(?i)(user.*created|created.*user|success)"
    },
    "CreateDatabase": {
      "Key": "g",
      "DatabasePrompt": "(?i)(database name|db name)",
      "SuccessPrompt": "(?i)(database.*created|created.*database|success)"
    },
    "GrantPrivileges": {
      "Key": "h",
      "UsernamePrompt": "(?i)(user.?name|mysql user)",
      "IpPrompt": "(?i)(ip|host)",
      "DatabasePrompt": "(?i)(database name|db name)",
      "PasswordPrompt": "(?i)password",
      "SuccessPrompt": "(?i)(privilege.*grant|permissions.*grant|success)"
    }
  },
  "Services": {
    "MainMenuKey": "b",
    "SubMenuPrompt": "(?i)(service|start|restart|select.*application|select.*option)",
    "ActionKeys": {
      "Start": "s",
      "Restart": "r"
    },
    "ServiceKeys": {
      "AppServer": "a",
      "Concentrator": "b",
      "Report Server": "c",
      "MediaSign": "d"
    },
    "SuccessPrompt": "(?i)(started|restarted|success)"
  },
  "Ssl": {
    "MainMenuKey": "n",
    "SubMenuPrompt": "(?i)(ssl option|enable ssl|disable ssl|concentrator|report server)",
    "Options": {
      "Concentrator": { "Enable": "a", "Disable": "b" },
      "Report Server": { "Enable": "c", "Disable": "d" }
    },
    "ContinuePrompt": "(?i)(hit enter to continue|press enter|press any key|continue)",
    "SuccessPrompt": "(?i)(ssl|enabled|disabled|concentrator|report|success|error|not found)"
  }
}
'@

