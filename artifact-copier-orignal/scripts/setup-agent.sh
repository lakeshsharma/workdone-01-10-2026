#!/usr/bin/env bash
# setup-agent.sh
# Run this ONCE on the Ubuntu Jenkins agent to install all required tools.
# Run as a user with sudo access.

set -Eeuo pipefail

echo "=== Installing artifact-copier dependencies ==="

sudo apt-get update -q

sudo apt-get install -y \
    smbclient \   # SMB/Windows share transfers
    aria2 \       # parallel downloads (used if you ever add a URL-based source)
    rsync \       # SSH transfers (usually pre-installed, included for safety)
    sshpass \     # allows rsync to use a password without interactive prompt
    curl \        # fallback HTTP downloader
    python3       # used by other scripts in the suite

echo ""
echo "=== Versions installed ==="
smbclient  --version
aria2c     --version | head -1
rsync      --version | head -1
sshpass    -V 2>&1 | head -1
curl       --version | head -1
python3    --version

echo ""
echo "=== Done ==="
echo ""
echo "Now install the Jenkins 'Copy Artifact' plugin (one-time, by Jenkins admin):"
echo "  Manage Jenkins → Plugins → Available → search 'Copy Artifact' → Install"
