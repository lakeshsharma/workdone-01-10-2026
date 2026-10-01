# Jenkins Agent Recovery — Windows desktop tool

Give the operator only [AgentRecovery.exe](release/AgentRecovery.exe). It is a native Windows app published as one self-contained EXE. The .NET runtime, SSH client, and Linux probe are bundled. The operator PC needs no installer, browser, Python, or separate config file.

## First launch

Open **Settings**. Six supplied Linux agents are prefilled with their Jenkins names, IPs, and SSH usernames. Their passwords and workspace roots are blank. Double-click an agent to enter its individual SSH password, workspace root, and optional protected paths. Enter the Jenkins HTTPS URL, API user, and token, then click **Save settings**. Use **Add agent** for more machines; **Add supplied agents** restores any missing presets without duplicating existing rows.

**Workspace root** is the parent directory containing that agent's Jenkins job workspaces, such as `/home/jenkins/workspace`. The tool only browses and deletes beneath this folder. **Protected paths** are optional absolute paths that must never be deleted, such as `/home/jenkins/workspace/critical-job`. Separate multiple paths with semicolons. Selecting a parent that contains a protected path is also blocked.

There is no host-key field. On the first SSH connection, the app shows the server's SHA256 identity and asks the operator to trust it. Verify the identity through a trusted source before accepting. The accepted identity is saved in encrypted settings; unexpected changes are refused. **Reset SSH trust** in the agent editor is for an intentional agent rebuild or SSH key rotation.

Settings are encrypted for the current Windows user in `%LOCALAPPDATA%\OneLinkAgentRecovery\settings.dat`. The app creates this file itself; it is not distributed with the EXE.

Right-click an agent on **Diagnose** or **Settings** and choose **Connect now** to open its SSH session. Choose **Disconnect** from the same menu to close it. The Diagnose table has an SSH connection column, and the bottom status bar shows **Connected** or **Disconnected** for the selected agent. Scans and folder browsing reuse an open session. **Test selected SSH** in Settings also opens and retains the session; it does not require a workspace root. Use **Test Jenkins API** to check the Jenkins URL and credentials independently. Jenkins expects the **Jenkins username and that user's Jenkins API token** together for HTTP Basic authentication; a token from another service is not a Jenkins API token.

An SSH timeout means the app could not reach the configured host and port. It occurs before checking the SSH password, workspace path, or Jenkins API credentials. Check the host/IP mapping, VPN, firewall, SSH port, and `sshd` service.

## Operator flow

1. On **Diagnose**, click **Scan all agents**. The app shows Jenkins state, free disk space, free inodes, largest workspace entry, a finding, and a short process sample.
2. Select an agent and click **Explore selected**. Expand folders to see nested folders and recursive sizes. Selecting a folder shows its path, size, owner UID, mode, and any measurement errors. Check the boxes beside one or more separate folders you want to review for deletion; the workspace root, files, and symlinks cannot be checked.
3. When deletion is the right action, click **Pause agent** and approve it. Jenkins stops assigning new builds; wait for running builds to finish.
4. Click **Review checked folders for deletion**. The app measures every checked folder and shows the exact paths, individual sizes, and total size. For one folder, type its complete path; for multiple folders, type the displayed approval phrase. After approval, it rechecks Jenkins before each deletion and verifies each folder against its reviewed snapshot. If any deletion fails, it stops and reports how many completed.
5. Verify free space, then click **Resume selected agent**. The app leaves the agent paused after deletion so you control when it resumes.

The app refuses to delete the workspace root, symlinks, folders containing protected paths, folders with incomplete measurements, or folders on agents that are not temporarily offline and idle. Audit records are stored at `%LOCALAPPDATA%\OneLinkAgentRecovery\audit.jsonl`.

The **Live run log** panel at the bottom of the window shows timestamped connection checks, scans, folder measurements, approvals, results, and errors as they happen. **Clear** empties the current display and **Copy** copies it for troubleshooting. Passwords and API tokens are not written to this panel.

High CPU alone is not a disk-space cause. The scan shows process CPU and write I/O separately; write I/O may be unavailable for processes owned by another account.

## Agent and Jenkins requirements

- Jenkins must be reachable via HTTPS. The API account needs node read and temporarily-offline permissions.
- Linux agents need an SSH server and `python3` in PATH. The probe source is embedded in the EXE and sent over SSH; nothing is installed on the agents.
- The SSH login needs read access to measure workspace folders and permission to delete any approved folder. The app reports access errors instead of changing permissions automatically.
- The possible Windows Jenkins agent is not yet supported.
- Quotas, deleted-but-open files, historical growth, and exact process-to-build attribution are not yet diagnosed.
- Live testing against your Jenkins and one representative agent is still required before production cleanup.

## Build from source

With the .NET 10 SDK on a Windows development machine:

```powershell
dotnet publish AgentRecovery/AgentRecovery.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None -p:DebugSymbols=false -o release
```

The only file to distribute is `release/AgentRecovery.exe`. See Microsoft's [single-file deployment guide](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview) and Jenkins' [remote API](https://www.jenkins.io/doc/book/using/remote-access-api/).
