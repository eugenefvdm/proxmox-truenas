#!/usr/bin/env bash
# Apply TrueNAS coexistence on a single Proxmox node (8 or 9).
# Usage: ./update/apply.sh <node>   e.g.  ./update/apply.sh pve9-tn25.10.example.com
# Copies pre-built ZFSPlugin (from update/) + LunCmd to the node. PVE 8: optionally patches pvemanagerlib.js.
# To restore stock: copy update/original_files/proxmoxN.ZFSPlugin.pm to the node as ZFSPlugin.pm.

set -euo pipefail

NODE="${1:-}"
PATH_ZFS="/usr/share/perl5/PVE/Storage/ZFSPlugin.pm"
PATH_LUNCMD="/usr/share/perl5/PVE/Storage/LunCmd/TrueNAS.pm"
PATH_NATIVE="/usr/share/perl5/PVE/Storage/Custom/TrueNASPlugin.pm"
PATH_MANAGER="/usr/share/pve-manager/js/pvemanagerlib.js"
REMOTE_DIR="/root/coexist-applied"
PATCH_ARGS="-p1 -b --ignore-whitespace --verbose"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UPDATED_ZFS_8="$SCRIPT_DIR/proxmox8.updated.ZFSPlugin.pm"
UPDATED_ZFS_9="$SCRIPT_DIR/proxmox9.updated.ZFSPlugin.pm"
LUNCMD="$REPO_ROOT/perl5/PVE/Storage/LunCmd/TrueNAS.pm"

usage() {
    echo "Usage: $0 <node>"
    echo "  e.g.  $0 pve9-tn25.10.example.com"
    echo "  e.g.  $0 pve8-tn24.04.example.com"
    exit 1
}

[[ -n "$NODE" ]] || usage

echo "Apply TrueNAS coexistence on $NODE"
echo "Update dir: $SCRIPT_DIR"
read -p "Press Enter to continue or Ctrl+C to cancel."

# Pre-check: native plugin must be present
ssh -o ConnectTimeout=10 -o BatchMode=yes "root@$NODE" "test -f $PATH_NATIVE" || { echo "Install proxmox-truenas-native on $NODE first."; exit 1; }
echo "[OK] Native plugin present"

# Detect Proxmox major version
VER=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "root@$NODE" "dpkg-query -W proxmox-ve 2>/dev/null | awk '{print \$2}' | cut -d. -f1" || true)
[[ -z "$VER" ]] && VER=9
echo "Proxmox major version: $VER"

if [[ "$VER" == "9" ]]; then
    [[ -f "$UPDATED_ZFS_9" ]] || { echo "Missing $UPDATED_ZFS_9"; exit 1; }
    [[ -f "$LUNCMD" ]] || { echo "Missing $LUNCMD"; exit 1; }
    scp -q "$UPDATED_ZFS_9" "root@$NODE:$PATH_ZFS"
    scp -q "$LUNCMD" "root@$NODE:$PATH_LUNCMD"
    echo "[OK] ZFSPlugin.pm and LunCmd/TrueNAS.pm copied"
elif [[ "$VER" == "8" ]]; then
    [[ -f "$UPDATED_ZFS_8" ]] || { echo "Missing $UPDATED_ZFS_8"; exit 1; }
    [[ -f "$LUNCMD" ]] || { echo "Missing $LUNCMD"; exit 1; }
    scp -q "$UPDATED_ZFS_8" "root@$NODE:$PATH_ZFS"
    scp -q "$LUNCMD" "root@$NODE:$PATH_LUNCMD"
    echo "[OK] ZFSPlugin.pm and LunCmd/TrueNAS.pm copied"
    # Optional GUI patch for PVE 8
    if [[ -f "$REPO_ROOT/pve-manager/js/pvemanagerlib.js.8.patch" ]]; then
        ssh "root@$NODE" "mkdir -p $REMOTE_DIR"
        scp -q "$REPO_ROOT/pve-manager/js/pvemanagerlib.js.8.patch" "root@$NODE:$REMOTE_DIR/"
        if ssh "root@$NODE" "patch $PATCH_ARGS --dry-run $PATH_MANAGER < $REMOTE_DIR/pvemanagerlib.js.8.patch" 2>/dev/null; then
            ssh "root@$NODE" "patch $PATCH_ARGS $PATH_MANAGER < $REMOTE_DIR/pvemanagerlib.js.8.patch"
            echo "[OK] pvemanagerlib.js patched"
        else
            echo "[SKIP] pvemanagerlib.js patch skipped (not applicable)"
        fi
    fi
else
    echo "Unsupported Proxmox version $VER (only 8 and 9)"
    exit 1
fi

ssh "root@$NODE" "systemctl restart pvedaemon pvestatd pveproxy"
echo "[OK] Services restarted on $NODE"
echo "Done."
