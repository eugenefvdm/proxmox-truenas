# TrueNAS Old + New API Coexistence

Both storage types can run on the same Proxmox node: **`zfs:`** with `iscsiprovider truenas` (old TrueNAS 24.04–25.04) and **`truenas:`** (new TrueNAS 25.10+). The project’s APT packages only allow one at a time; this doc describes how to get both without maintaining your own packages.

## Strategy

1. Install **proxmox-truenas-native** only (do not install `proxmox-truenas`).
2. On each node, add the “patch” layer by hand: copy `LunCmd/TrueNAS.pm` and apply the ZFSPlugin patch. Do **not** remove `PVE/Storage/Custom/TrueNASPlugin.pm`.

Result: native plugin handles `truenas:`; patched ZFSPlugin handles `zfs:` + `iscsiprovider truenas`.

**Property names:** When both plugins are present, the ZFS patch uses **`zfs_truenas_*`** keys (e.g. `zfs_truenas_apiv4_host`) so SectionConfig does not see duplicate properties. LunCmd/TrueNAS.pm accepts both `zfs_truenas_*` and legacy `truenas_*`; existing `zfs:` entries that already use `truenas_apiv4_host` may still work if your config parser passes them through. For new `zfs:` storage or if you see validation errors, use `zfs_truenas_apiv4_host`, `zfs_truenas_apikey`, etc.

## Test nodes

We test on **at least two nodes** so migrations and cross-node behaviour can be verified:

- **hv02.vander.host**
- **hv09.vander.host**

## Prerequisites

- Repo (or patch files) available on the host or via copy.
- Proxmox 8 or 9; `proxmox-truenas-native` installed.
- Run commands as root on the Proxmox node (or via SSH with key).

---

## Commands by Proxmox version

Paths assume you are in the repo root (or adjust paths to where the patch files and `perl5/` live).

### Proxmox 9

**1. Backup (on node)**

```bash
cp -a /usr/share/perl5/PVE/Storage/ZFSPlugin.pm /usr/share/perl5/PVE/Storage/ZFSPlugin.pm.bak.$(date +%Y%m%d%H%M%S)
cp -a /usr/share/pve-manager/js/pvemanagerlib.js /usr/share/pve-manager/js/pvemanagerlib.js.bak.$(date +%Y%m%d%H%M%S)
```

**2. Patch dry-run (no changes)**

```bash
patch -p1 -b --ignore-whitespace --verbose --dry-run -d /usr/share/perl5/PVE/Storage -i /path/to/perl5/PVE/Storage/ZFSPlugin.pm.9.patch
patch -p1 -b --ignore-whitespace --verbose --dry-run -d /usr/share/pve-manager/js -i /path/to/pve-manager/js/pvemanagerlib.js.9.patch
```

**3. Apply patches**

```bash
patch -p1 -b --ignore-whitespace --verbose -d /usr/share/perl5/PVE/Storage -i /path/to/perl5/PVE/Storage/ZFSPlugin.pm.9.patch
patch -p1 -b --ignore-whitespace --verbose -d /usr/share/pve-manager/js -i /path/to/pve-manager/js/pvemanagerlib.js.9.patch
```

**4. Copy LunCmd module**

```bash
cp /path/to/perl5/PVE/Storage/LunCmd/TrueNAS.pm /usr/share/perl5/PVE/Storage/LunCmd/
```

**5. Perl syntax check (dry-run)**

```bash
perl -c /usr/share/perl5/PVE/Storage/ZFSPlugin.pm
perl -c /usr/share/perl5/PVE/Storage/LunCmd/TrueNAS.pm
```

**6. Restart services**

```bash
systemctl restart pvedaemon pvestatd pveproxy
```

---

### Proxmox 8

Same flow, use the **`.8`** patch files:

**Patch dry-run**

```bash
patch -p1 -b --ignore-whitespace --verbose --dry-run -d /usr/share/perl5/PVE/Storage -i /path/to/perl5/PVE/Storage/ZFSPlugin.pm.8.patch
patch -p1 -b --ignore-whitespace --verbose --dry-run -d /usr/share/pve-manager/js -i /path/to/pve-manager/js/pvemanagerlib.js.8.patch
```

**Apply patches**

```bash
patch -p1 -b --ignore-whitespace --verbose -d /usr/share/perl5/PVE/Storage -i /path/to/perl5/PVE/Storage/ZFSPlugin.pm.8.patch
patch -p1 -b --ignore-whitespace --verbose -d /usr/share/pve-manager/js -i /path/to/pve-manager/js/pvemanagerlib.js.8.patch
```

**Copy + Perl check** (same as Proxmox 9)

```bash
cp /path/to/perl5/PVE/Storage/LunCmd/TrueNAS.pm /usr/share/perl5/PVE/Storage/LunCmd/
perl -c /usr/share/perl5/PVE/Storage/ZFSPlugin.pm
perl -c /usr/share/perl5/PVE/Storage/LunCmd/TrueNAS.pm
```

---

## Recovery: pvedaemon fails with "duplicate property 'truenas_apiv4_host'"

If you applied the ZFS patch while the native TrueNAS plugin was also installed, SectionConfig can hit a duplicate-property error and pvedaemon will not start. **Restore the ZFSPlugin backup** on that node (the script creates `.bak.TIMESTAMP`), then re-apply using the **updated** patches in this repo (they use `zfs_truenas_*` property names to avoid the conflict).

**One-time restore on the broken node (e.g. hv02):**

```bash
# On the node (ssh root@hv02.vander.host or from the host)
cp -a /usr/share/perl5/PVE/Storage/ZFSPlugin.pm.bak.TIMESTAMP /usr/share/perl5/PVE/Storage/ZFSPlugin.pm
systemctl restart pvedaemon pvestatd pveproxy
```

Replace `TIMESTAMP` with the suffix from your backup (e.g. `20260223163316`). Then re-run the coexistence procedure using the current repo (updated patches + LunCmd) so both plugins can load.

---

## After upgrades

If `libpve-storage-perl` or `pve-manager` is upgraded, ZFSPlugin (and possibly pvemanagerlib) may be overwritten. Re-apply the matching patch and restart services. Consider holding `libpve-storage-perl` if you want to control when that happens.

---

## Optional automation

One script for any node (run from repo root):

```bash
./scripts/coexist-apply.sh <node>
```

Examples:

```bash
chmod +x scripts/coexist-apply.sh
./scripts/coexist-apply.sh hv02.vander.host   # Proxmox 9: copies pre-built ZFSPlugin + LunCmd
./scripts/coexist-apply.sh hv09.vander.host    # Proxmox 8: patches ZFSPlugin + LunCmd + optional GUI
```

The script detects Proxmox version on the node and uses the right method (pre-built for 9, patch for 8). One confirmation at the start; no server-side backups (restore from repo’s `updated_files/proxmox9.ZFSPlugin.pm` if needed).
