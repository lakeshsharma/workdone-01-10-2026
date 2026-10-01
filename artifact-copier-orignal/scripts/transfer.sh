#!/usr/bin/env bash
# transfer.sh — called by Jenkinsfile to push artifacts to SMB or SSH
#
# Usage (called by Jenkinsfile, not directly):
#   transfer.sh smb
#   transfer.sh ssh
#
# Environment variables set by Jenkinsfile before calling this script:
#
#   Always required:
#     INCOMING_DIR   — local directory containing the downloaded artifact(s)
#     DEST_USER      — username for the destination
#     DEST_PASS      — password for the destination (never logged)
#
#   For smb mode:
#     SMB_HOST       — parsed by Jenkinsfile from the UNC path
#     SMB_SHARE      — parsed by Jenkinsfile from the UNC path
#     SMB_SUBDIR     — parsed by Jenkinsfile from the UNC path (may be empty)
#
#   For ssh mode:
#     SSH_TARGET_HOST — destination hostname or IP
#     SSH_TARGET_PATH — remote directory path

set -Eeuo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[$(date '+%H:%M:%S')] $*"; }
ok()   { echo "[ OK  ] $*"; }

MODE="${1:-}"
[[ "$MODE" == "smb" || "$MODE" == "ssh" ]] || die "Usage: transfer.sh <smb|ssh>"

# ── find artifact(s) in INCOMING_DIR ─────────────────────────────────────────
: "${INCOMING_DIR:?INCOMING_DIR env var not set}"
: "${DEST_USER:?DEST_USER env var not set}"
: "${DEST_PASS:?DEST_PASS env var not set}"

shopt -s nullglob
FILES=("$INCOMING_DIR"/*)
shopt -u nullglob

[[ ${#FILES[@]} -gt 0 ]] || die "No files found in $INCOMING_DIR"

info "Files to transfer (${#FILES[@]}):"
for f in "${FILES[@]}"; do
    info "  $(basename "$f")  ($(du -h "$f" | cut -f1))"
done

# ═════════════════════════════════════════════════════════════════════════════
# SMB TRANSFER
# ═════════════════════════════════════════════════════════════════════════════
if [[ "$MODE" == "smb" ]]; then

    : "${SMB_HOST:?SMB_HOST env var not set}"
    : "${SMB_SHARE:?SMB_SHARE env var not set}"

    command -v smbclient &>/dev/null \
        || die "smbclient not installed. Run: sudo apt install smbclient"

    info "Destination: //$SMB_HOST/$SMB_SHARE"
    [[ -n "${SMB_SUBDIR:-}" ]] && info "Subdirectory: $SMB_SUBDIR"

    # Write credentials to a temp file so the password never appears
    # on the command line (invisible to 'ps aux' and never in logs)
    CRED_FILE=$(mktemp)
    chmod 600 "$CRED_FILE"
    trap 'rm -f "$CRED_FILE"' EXIT
    printf 'username=%s\npassword=%s\n' "$DEST_USER" "$DEST_PASS" > "$CRED_FILE"

    # Build the smbclient 'cd' command — skip if subdir is empty
    if [[ -n "${SMB_SUBDIR:-}" ]]; then
        CD_CMD="cd \"$SMB_SUBDIR\";"
    else
        CD_CMD=""
    fi

    for FILE in "${FILES[@]}"; do
        FILENAME=$(basename "$FILE")
        FILESIZE=$(du -h "$FILE" | cut -f1)
        info "Copying $FILENAME ($FILESIZE) → SMB ..."

        smbclient "//$SMB_HOST/$SMB_SHARE" \
            --authentication-file="$CRED_FILE" \
            -m SMB3 \
            -c "${CD_CMD} put \"$FILE\" \"$FILENAME\""

        ok "$FILENAME transferred."
    done

    info "All SMB transfers complete."

# ═════════════════════════════════════════════════════════════════════════════
# SSH / RSYNC TRANSFER
# ═════════════════════════════════════════════════════════════════════════════
elif [[ "$MODE" == "ssh" ]]; then

    : "${SSH_TARGET_HOST:?SSH_TARGET_HOST env var not set}"
    : "${SSH_TARGET_PATH:?SSH_TARGET_PATH env var not set}"

    command -v sshpass &>/dev/null \
        || die "sshpass not installed. Run: sudo apt install sshpass"
    command -v rsync &>/dev/null \
        || die "rsync not installed. Run: sudo apt install rsync"

    info "Destination: $DEST_USER@$SSH_TARGET_HOST:$SSH_TARGET_PATH/"

    for FILE in "${FILES[@]}"; do
        FILENAME=$(basename "$FILE")
        FILESIZE=$(du -h "$FILE" | cut -f1)
        info "Copying $FILENAME ($FILESIZE) → SSH ..."

        # SSHPASS env var is read by sshpass -e
        # Password never appears in 'ps aux' or logs this way
        SSHPASS="$DEST_PASS" sshpass -e rsync \
            --progress \
            --partial \
            --inplace \
            -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
            "$FILE" \
            "$DEST_USER@$SSH_TARGET_HOST:$SSH_TARGET_PATH/"

        ok "$FILENAME transferred."
    done

    info "All SSH transfers complete."

fi
